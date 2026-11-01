import Foundation

public struct HelperVerification: Equatable, Sendable {
    public let path: String
    public init(path: String) { self.path = path }
}

public enum DesktopHelperProbe {
    /// Fixed, read-only bootstrap. Model text never becomes PowerShell source.
    public static func discoveryCommand() throws -> String {
        let payload: JSONValue = ["version": 1, "operation": "capabilities", "arguments": [:], "roots": []]
        let encoded = try payload.data().base64EncodedString()
        let script = """
        $ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
        $bbPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BlackBox-iOS\\BlackBoxHelper.ps1'
        if (-not (Test-Path -LiteralPath $bbPath -PathType Leaf)) { throw 'Install BlackBoxHelper.ps1 in LocalAppData/BlackBox-iOS, then check the helper again.' }
        $bbOutput=& $bbPath -PayloadB64 '\(encoded)'
        $bbEvidence=($bbOutput -join [Environment]::NewLine) | ConvertFrom-Json
        $bbEvidence | Add-Member -NotePropertyName helperPath -NotePropertyValue $bbPath -Force
        $bbEvidence | ConvertTo-Json -Depth 10 -Compress
        """
        guard let bytes = script.data(using: .utf16LittleEndian) else { throw BBError.invalid("Could not encode helper discovery.") }
        return "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -EncodedCommand " + bytes.base64EncodedString()
    }
    public static func evaluate(_ payload: JSONValue, configuredPath: String) throws -> HelperVerification {
        guard let evidence = HelperEvidence.parse(payload, operation: "capabilities") else {
            throw BBError.setup("Windows helper did not return its capability check. Install the helper on the selected PC, then use Find and check helper in Settings.")
        }
        guard evidence["ok"].bool == true else {
            let reason = ContentRedactor.clean(String((evidence["error"].string ?? "Capability check failed").prefix(300)))
            throw BBError.setup("Windows helper: " + reason)
        }
        let required: Set<String> = ["open_url", "open_alias", "open_path", "open_application", "inspect_resources", "media_control", "create_folder", "move_file", "validate_path"]
        guard evidence["os"].string == "Windows", evidence["runtime"].string?.hasPrefix("PowerShell ") == true,
              required.isSubset(of: Set(evidence["supported"].array.compactMap(\.string))) else {
            throw BBError.setup("The installed Windows helper does not support this app's commands. Update BlackBoxHelper.ps1 and check again.")
        }
        let configured = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = configured.isEmpty ? evidence["helperPath"].string : configured else { throw BBError.wire("Helper discovery returned no script path.") }
        let canonical = try ToolPolicy.windowsPath(path)
        _ = try HelperCommand.make(path: canonical, operation: "capabilities", arguments: [:], roots: [])
        return HelperVerification(path: canonical)
    }
    public static func check(deviceID: String, path: String, tools: [JSONValue], mcp: MCPClient, token: String) async throws -> HelperVerification {
        guard !deviceID.isEmpty,
              let schema = tools.first(where: { $0["name"].string == "start_process" }),
              schema["inputSchema"]["properties"]["deviceId"].object != nil else {
            throw BBError.setup("RDC did not expose a device-bound command tool. Refresh paired devices and check again.")
        }
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = try path.isEmpty ? discoveryCommand() : HelperCommand.make(path: path, operation: "capabilities", arguments: [:], roots: [])
        let args: JSONValue = ["deviceId": .string(deviceID), "command": .string(command), "shell": "powershell.exe", "timeout_ms": 3000]
        let allowed = Set(schema["inputSchema"]["properties"].object?.keys.map { $0 } ?? [])
        guard Set(args.object!.keys).isSubset(of: allowed), schema["inputSchema"]["required"].array.compactMap(\.string).allSatisfy({ args[$0] != .null }) else { throw BBError.setup("RDC's command schema differs from this app. Refresh the connection before checking the helper.") }
        try Task.checkCancellation()
        let raw = try await mcp.call("start_process", arguments: args, token: token)
        return try evaluate(MCPClient.payload(raw), configuredPath: path)
    }
}

public struct DesktopHelperSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, checking, ready, failed }
    public var phase: Phase = .idle
    public var deviceID: String?
    public var inputPath = ""
    public var path = ""
    public var message = "Windows helper needs a connection check."
    public init() {}
}

/// Shares one bounded read-only check among foreground/request/manual callers.
/// A canceled or timed-out probe can never enable a new device/path later.
@MainActor public final class DesktopHelperController {
    public private(set) var snapshot = DesktopHelperSnapshot()
    public var onChange: ((DesktopHelperSnapshot) -> Void)?
    private var generation = UUID()
    private var job: Task<HelperVerification, Error>?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var pending: CheckedContinuation<HelperVerification, Error>?
    public init() {}
    private func publish(_ state: DesktopHelperSnapshot) { snapshot = state; onChange?(state) }
    public func invalidate(_ message: String = "Windows helper needs a connection check.") {
        generation = UUID(); worker?.cancel(); timer?.cancel(); worker = nil; timer = nil
        let waiter = pending; pending = nil; job = nil; waiter?.resume(throwing: CancellationError())
        var state = DesktopHelperSnapshot(); state.message = message; publish(state)
    }
    public func check(deviceID: String, path: String, timeoutNanoseconds: UInt64 = 25_000_000_000,
                      probe: @escaping @MainActor () async throws -> HelperVerification) async throws -> HelperVerification {
        try Task.checkCancellation()
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if snapshot.phase == .checking, snapshot.deviceID == deviceID, snapshot.inputPath == path, let job { return try await job.value }
        invalidate(); let epoch = generation
        var state = DesktopHelperSnapshot(); state.phase = .checking; state.deviceID = deviceID; state.inputPath = path
        state.message = "Checking desktop commands…"; publish(state)
        let task = Task<HelperVerification, Error> {
            guard epoch == generation else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                worker = Task { [weak self] in
                    do { let result = try await probe(); self?.finish(.success(result), epoch: epoch) }
                    catch { self?.finish(.failure(error), epoch: epoch) }
                }
                timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
                    self?.finish(.failure(BBError.setup("The Windows helper check timed out. Keep the selected PC's RDC agent running, then check again.")), epoch: epoch)
                }
            }
        }
        job = task; return try await task.value
    }
    private func finish(_ result: Result<HelperVerification, Error>, epoch: UUID) {
        guard generation == epoch, snapshot.phase == .checking else { return }
        generation = UUID(); timer?.cancel(); worker?.cancel(); timer = nil; worker = nil; job = nil
        var state = snapshot
        switch result {
        case .success(let value): state.phase = .ready; state.path = value.path; state.message = "Desktop commands ready"
        case .failure(let error): state.phase = .failed; state.message = error is CancellationError ? "Windows helper check canceled" : error.localizedDescription
        }
        let waiter = pending; pending = nil
        publish(state); waiter?.resume(with: result)
    }
}
