import Foundation
import Combine
import UIKit
import Darwin
import BlackBoxCore

@MainActor final class AppModel: ObservableObject {
    @Published var settings = AppSettings()
    @Published var messages: [ChatMessage] = []
    @Published var tasks: [TaskRecord] = []
    @Published var actions: [ActionRecord] = []
    @Published var memories: [Memory] = []
    @Published var aliases: [FolderAlias] = []
    @Published var draft = ""
    @Published var streamingText = ""
    @Published var busy = false
    @Published var error: String?
    @Published var geminiState = GeminiValidationSnapshot()
    @Published var voiceState = ElevenValidationSnapshot()
    @Published var helperState = DesktopHelperSnapshot()
    @Published var checks: [String] = []
    @Published var reviewTool: ValidatedTool?
    @Published var hasGeminiKey = false
    @Published var hasVoiceKey = false
    let rdc = RDCSession()
    let audio = AudioController()
    private var repository: Repository?
    private let vault = KeychainStore()
    private let geminiValidation = GeminiValidationController()
    private let elevenValidation = ElevenValidationController()
    private let helper = DesktopHelperController()
    private var running: Task<Void, Never>?
    private var activeID: String?
    private var reviewContinuation: CheckedContinuation<Bool, Never>?
    private var foreground = false
    private var foregroundEpoch = UUID()
    var selected: PCDevice? { rdc.devices.first { $0.id == settings.selectedDeviceID } }
    var helperVerified: Bool {
        foreground && rdc.signedIn && selected?.online == true && helperState.phase == .ready &&
        helperState.deviceID == settings.selectedDeviceID && helperState.path == settings.helperPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var helperChecking: Bool { helperState.phase == .checking }
    var helperStatus: String {
        guard rdc.signedIn else { return "Sign in to RDC to connect your PC." }
        guard let selected else { return "Select a PC in Computer, then check the Windows helper." }
        guard selected.online else { return "Selected PC is offline. Keep its RDC agent running." }
        return helperState.message
    }
    var pcStatus: String { helperVerified ? "PC ready" : helperChecking ? "Checking PC" : selected?.online == true ? "PC setup" : "PC unavailable" }
    var hardwareIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else { return "unavailable" }
        return String(cString: bytes)
    }
    init() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("BlackBox", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            var values = URLResourceValues(); values.isExcludedFromBackup = true; var protectedRoot = root; try protectedRoot.setResourceValues(values)
            let store = try Repository(path: root.appendingPathComponent("blackbox.sqlite").path)
            repository = store
            settings = try store.all(AppSettings.self, kind: "settings").first ?? AppSettings()
            let speechModel = ElevenLabsClient.normalizedModelID(settings.speechModel)
            if speechModel != settings.speechModel {
                settings.speechModel = speechModel; try store.save(settings, kind: "settings", id: "main")
            }
            checks = try store.all([String].self, kind: "diagnostics").first ?? []
            try store.recover(); try reload(); try refreshKeyPresence()
        } catch { self.error = "Local startup failed: \(error.localizedDescription). Existing data was preserved." }
        geminiValidation.onChange = { [weak self] in self?.geminiState = $0 }
        if hasGeminiKey { geminiValidation.keyStored() }
        elevenValidation.onChange = { [weak self] in self?.voiceState = $0 }
        if hasVoiceKey { elevenValidation.keyStored() }
        helper.onChange = { [weak self] state in
            guard let self else { return }
            self.helperState = state
            if state.phase == .ready, self.foreground, state.deviceID == self.settings.selectedDeviceID {
                self.settings.helperPath = state.path
                do { try self.saveSettings() } catch { self.error = error.localizedDescription }
            }
        }
        audio.onFinal = { [weak self] text in
            guard let self, !self.busy else { return }; self.draft = text; self.send()
        }
    }
    func reload() throws {
        guard let store = repository else { throw BBError.setup("Local storage unavailable.") }
        messages = try store.all(ChatMessage.self, kind: "message")
        tasks = try store.all(TaskRecord.self, kind: "task").reversed()
        actions = try store.all(ActionRecord.self, kind: "action").reversed()
        memories = try store.all(Memory.self, kind: "memory"); aliases = try store.all(FolderAlias.self, kind: "alias")
    }
    func perform(_ job: @escaping @MainActor () async throws -> Void) { Task { do { try await job() } catch { self.error = error.localizedDescription } } }
    func saveSettings() throws { try repository?.save(settings, kind: "settings", id: "main") }
    func refreshKeyPresence() throws { hasGeminiKey = !(try vault.string("gemini")).isEmpty; hasVoiceKey = !(try vault.string("elevenlabs")).isEmpty }
    func saveKey(_ key: String, provider: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw BBError.invalid("Enter a nonempty API key.") }
        guard ["gemini", "elevenlabs"].contains(provider) else { throw BBError.invalid("Unknown key provider.") }
        try vault.set(Data(key.utf8), account: provider); try refreshKeyPresence()
        if provider == "gemini" { geminiValidation.keyStored(); validateGemini() }
        else { audio.stopSpeech(); elevenValidation.keyStored(); validateVoice() }
    }
    func deleteKey(_ provider: String) throws {
        try vault.delete(provider); try refreshKeyPresence()
        if provider == "gemini" { geminiValidation.clear() }
        else { elevenValidation.clear(); audio.stopSpeech() }
    }
    func gemini() throws -> GeminiClient { GeminiClient(key: try vault.string("gemini"), model: settings.model) }
    func voice() throws -> ElevenLabsClient { ElevenLabsClient(key: try vault.string("elevenlabs"), voiceID: settings.voiceID, model: settings.speechModel) }
    func validateGemini() {
        do {
            settings.model = GeminiClient.normalizedModelID(settings.model)
            try saveSettings()
            geminiValidation.check(key: try vault.string("gemini"), model: settings.model)
        } catch { geminiValidation.fail(error) }
    }
    func checkSavedGeminiKey() {
        if hasGeminiKey, geminiState.phase == .stored { validateGemini() }
    }
    func cancelGeminiValidation() { geminiValidation.cancel() }
    func geminiModelChanged(_ value: String) {
        geminiValidation.selectModel(value)
        do { try saveSettings() } catch { self.error = error.localizedDescription }
    }
    private func normalizeVoiceSettings() throws {
        settings.voiceID = ElevenLabsClient.normalizedVoiceID(settings.voiceID)
        settings.speechModel = ElevenLabsClient.normalizedModelID(settings.speechModel)
        try saveSettings()
    }
    func validateVoice() {
        do {
            try normalizeVoiceSettings()
            elevenValidation.check(key: try vault.string("elevenlabs"), voiceID: settings.voiceID, model: settings.speechModel)
        } catch { elevenValidation.fail(error) }
    }
    func cancelVoiceValidation() { elevenValidation.cancel() }
    func checkSavedVoiceKey() {
        if hasVoiceKey, !settings.voiceID.isEmpty, voiceState.phase == .stored { validateVoice() }
    }
    func voiceIDChanged(_ value: String) {
        elevenValidation.voiceChanged(value)
        do { try saveSettings() } catch { self.error = error.localizedDescription }
    }
    func speechModelChanged(_ value: String) {
        elevenValidation.selectModel(value)
        do { try saveSettings() } catch { self.error = error.localizedDescription }
    }
    func testGemini() async throws {
        let reply = try await gemini().generate(history: [["role": "user", "parts": [["text": "Reply with: Black_Box online."]]]], system: "Keep the response to one sentence.", tools: [], grounded: false, onText: { _ in })
        recordCheck("PASS · Gemini direct response: \(reply.text) · \(reply.tokens) reported tokens")
    }
    func recordCheck(_ text: String) {
        checks.insert("\(Date().formatted(date: .abbreviated, time: .standard)) · \(text)", at: 0)
        do { try repository?.save(checks, kind: "diagnostics", id: "main") } catch { self.error = error.localizedDescription }
    }
    func testVoice() throws {
        try normalizeVoiceSettings()
        audio.speak("Black Box online. A promising start.", client: try voice())
        recordCheck("STARTED · ElevenLabs playback test. Confirm audible output on the device.")
    }
    func select(_ id: String?) throws {
        guard !busy else { throw BBError.invalid("Cancel or finish the active task before selecting another PC.") }
        if settings.selectedDeviceID != id { helper.invalidate(); settings.selectedDeviceID = id; try saveSettings() }
        Task { if settings.selectedDeviceID == id { await checkHelperIfNeeded() } }
    }
    func helperPathChanged(_ value: String) {
        if helperState.phase != .ready || helperState.path != value.trimmingCharacters(in: .whitespacesAndNewlines) { helper.invalidate() }
        do { try saveSettings() } catch { self.error = error.localizedDescription }
    }
    func devicePresenceChanged() {
        if selected?.online != true { helper.invalidate() }
    }
    func checkHelperIfNeeded() async {
        guard foreground, rdc.signedIn, selected?.online == true, !helperVerified else { return }
        do { try await verifyHelper() } catch { /* Inline status carries setup failures; public chat remains available. */ }
    }
    func verifyHelper() async throws {
        guard foreground else { throw CancellationError() }
        guard let device = selected, device.online else { throw BBError.setup("Select an online PC first.") }
        let path = settings.helperPath, epoch = foregroundEpoch
        _ = try await helper.check(deviceID: device.id, path: path) { [rdc] in
            let token = try await rdc.accessToken()
            return try await DesktopHelperProbe.check(deviceID: device.id, path: path, tools: rdc.tools, mcp: rdc.mcp, token: token)
        }
        try Task.checkCancellation()
        guard foreground, epoch == foregroundEpoch, settings.selectedDeviceID == device.id, helperVerified else { throw CancellationError() }
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        do {
            guard text.count <= 12000 else { throw BBError.invalid("Keep each request under 12,000 characters.") }
            guard let store = repository else { throw BBError.setup("Local storage unavailable.") }
            let model = try gemini()
            let task = try store.commit(input: text, deviceID: settings.selectedDeviceID)
            draft = ""; streamingText = ""; busy = true; activeID = task.id; audio.stopSpeech(); try reload()
            running = Task {
                defer { busy = false; activeID = nil; running = nil; streamingText = "" }
                do {
                    await checkHelperIfNeeded()
                    try Task.checkCancellation()
                    guard foreground, settings.selectedDeviceID == task.deviceID else { throw CancellationError() }
                    // Freeze declarations only after the read-only connection check finishes.
                    let policy = ToolPolicy(device: selected, aliases: aliases, helperVerified: helperVerified)
                    let executor = DesktopExecutor(mcp: rdc.mcp, token: { [rdc] in try await rdc.accessToken() }, research: model, tools: rdc.tools, helperPath: settings.helperPath, aliases: aliases)
                    let engine = ConversationEngine(store: store, model: model, executor: executor, policy: policy, settings: settings, connectionStatus: helperStatus)
                    let reply = try await engine.run(taskID: task.id, onText: { [weak self] chunk in
                        await MainActor.run { self?.streamingText += chunk }
                    }, onChange: { [weak self] in do { try self?.reload() } catch { self?.error = error.localizedDescription } }, review: { [weak self] tool in
                        guard let self else { return false }
                        return await withCheckedContinuation { c in self.reviewContinuation = c; self.reviewTool = tool }
                    })
                    if !settings.mute { try speak(reply.text) }
                } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func confirmReview(_ approved: Bool) { reviewTool = nil; reviewContinuation?.resume(returning: approved); reviewContinuation = nil }
    func cancelTask() {
        if let activeID { do { try repository?.cancel(activeID); try reload() } catch { self.error = error.localizedDescription } }
        confirmReview(false); running?.cancel(); audio.cancelCapture()
        if helperChecking { helper.invalidate("Windows helper check canceled. Check again to enable desktop commands.") }
    }
    func suspend() {
        foreground = false; foregroundEpoch = UUID(); helper.invalidate()
        cancelTask(); geminiValidation.cancel(); elevenValidation.cancel(); audio.interrupt()
    }
    func resume() async {
        foreground = true; let epoch = foregroundEpoch
        do {
            if !busy { try repository?.recover(); try reload() }
            if rdc.signedIn {
                try await rdc.refreshDevices()
                guard foreground, epoch == foregroundEpoch else { return }
                devicePresenceChanged()
                await checkHelperIfNeeded()
                guard foreground, epoch == foregroundEpoch else { return }
                // Read existing call IDs only. Never redispatch an interrupted operation.
                if !busy {
                    for action in actions.filter({ $0.state == .unknown && $0.remoteCallID != nil }).prefix(10) {
                        do { try await reconcile(action) } catch { recordCheck("PENDING · Existing RDC call could not be reconciled: \(error.localizedDescription)") }
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func speak(_ text: String) throws {
        guard !settings.mute else { return }
        audio.speak(String(text.prefix(settings.maxSpeechCharacters)), client: try voice())
    }
    func saveMemory(_ value: Memory) throws { guard value.text.count <= 2000 else { throw BBError.invalid("Keep each memory under 2,000 characters.") }; try repository?.save(value, kind: "memory", id: value.id); try reload() }
    func deleteMemory(_ id: String) throws { try repository?.delete(kind: "memory", id: id); try reload() }
    func saveAlias(name: String, path: String) throws {
        guard let id = settings.selectedDeviceID else { throw BBError.setup("Select a PC for this alias.") }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, name.count <= 40, name.allSatisfy({ $0.isLetter || $0.isNumber || " _-".contains($0) }) else { throw BBError.invalid("Use a short folder name.") }
        let alias = FolderAlias(deviceID: id, name: name, path: try ToolPolicy.windowsPath(path))
        try repository?.save(alias, kind: "alias", id: alias.id); try reload()
    }
    func deleteAlias(_ id: String) throws { try repository?.delete(kind: "alias", id: id); try reload() }
    func reconcile(_ action: ActionRecord) async throws {
        guard !busy, let callID = action.remoteCallID, let id = action.deviceID else { throw BBError.setup("No retrievable remote call ID. Inspect actual PC state; no original operation will be resent.") }
        let token = try await rdc.accessToken()
        guard let schema = rdc.tools.first(where: { $0["name"].string == "get_tool_result" }) else { throw BBError.setup("RDC does not advertise remote result retrieval.") }
        var args: [String: JSONValue] = ["call_id": .string(callID)]
        if schema["inputSchema"]["properties"]["deviceId"].object != nil { args["deviceId"] = .string(id) }
        let result = try MCPClient.payload(await rdc.mcp.call("get_tool_result", arguments: .object(args), token: token))
        if let observedID = result["deviceId"].string, observedID != id { throw BBError.wire("Retrieved call belongs to a different device.") }
        var updated = action; updated.result = result
        // Record retrieval, but only explicit terminal states resolve uncertainty.
        if result["status"].string == "completed" { updated.state = result["result"]["isError"].bool == true ? .failed : .completed }
        else if result["status"].string == "failed" { updated.state = .failed }
        try repository?.save(updated, kind: "action", id: updated.id)
        if let store = repository, [.completed, .failed].contains(updated.state) {
            let task = try store.task(action.taskID)
            let outstanding = try store.all(ActionRecord.self, kind: "action").contains(where: { $0.taskID == action.taskID && $0.state == .unknown })
            if task.state == .unknown, !outstanding {
                try store.state(action.taskID, .blocked, detail: "Remote result reconciled. Conversation was interrupted and has not been resumed; inspect the observed result before a new request.")
            }
        }
        try reload()
    }
}
