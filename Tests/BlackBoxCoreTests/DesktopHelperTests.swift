import XCTest
@testable import BlackBoxCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let fixturePath = "C:\\Users\\Fixture\\AppData\\Local\\BlackBox-iOS\\BlackBoxHelper.ps1"
private func capabilityFixture() -> JSONValue {
    ["marker": "BLACKBOX_HELPER_V1", "operation": "capabilities", "ok": true, "os": "Windows", "runtime": "PowerShell 5.1.19041.0",
     "supported": ["open_url", "open_alias", "open_path", "open_application", "inspect_resources", "media_control", "create_folder", "move_file", "validate_path"],
     "helperPath": .string(fixturePath)]
}
private let commandSchema: JSONValue = ["name": "start_process", "inputSchema": ["type": "object", "properties": ["deviceId": ["type": "string"], "command": ["type": "string"], "shell": ["type": "string"], "timeout_ms": ["type": "number"]], "required": ["command"]]]

final class DesktopHelperProbeTests: XCTestCase {
    func testObservedCLIXMLWrapperAndDiscoveredPathAreAccepted() throws {
        let output = "Process started with PID 1234\nInitial output:\n#< CLIXML\r\n" + capabilityFixture().text() + "\r\n<Objs Version=\"1.1.0.1\"></Objs>\nProcess finished execution"
        XCTAssertEqual(try DesktopHelperProbe.evaluate(["text": .string(output)], configuredPath: " \n").path, fixturePath)
    }
    func testConfiguredPathCannotBeReplacedByOutput() throws {
        let path = "C:\\Reviewed\\BlackBoxHelper.ps1"
        XCTAssertEqual(try DesktopHelperProbe.evaluate(capabilityFixture(), configuredPath: " \(path)\n").path, path)
    }
    func testMissingIncompleteOrWrongCapabilitiesNeverEnableTools() {
        for change: JSONValue in [[:], ["text": "Process started with PID 1234"], ["marker": "BLACKBOX_HELPER_V1", "operation": "open_url", "ok": true]] {
            XCTAssertThrowsError(try DesktopHelperProbe.evaluate(change, configuredPath: fixturePath))
        }
        for (field, value): (String, JSONValue) in [("marker", "other"), ("os", "Linux"), ("runtime", "unknown"), ("supported", ["open_url"])] {
            var evidence = capabilityFixture().object!; evidence[field] = value
            XCTAssertThrowsError(try DesktopHelperProbe.evaluate(.object(evidence), configuredPath: fixturePath), field)
        }
    }
    func testDiscoveryRequiresAnUnambiguousHelperPathAndRedactsFailure() {
        for path in ["", "C:\\Other.ps1", "C:\\..\\BlackBoxHelper.ps1", "\\\\server\\BlackBoxHelper.ps1"] {
            var evidence = capabilityFixture().object!; evidence["helperPath"] = .string(path)
            XCTAssertThrowsError(try DesktopHelperProbe.evaluate(.object(evidence), configuredPath: ""))
        }
        var failed = capabilityFixture().object!; failed["ok"] = false; failed["error"] = "Failed api_key=fixture-private-value"
        XCTAssertThrowsError(try DesktopHelperProbe.evaluate(.object(failed), configuredPath: "")) { error in
            XCTAssertFalse(error.localizedDescription.contains("fixture-private-value"))
        }
    }
    func testFixedDiscoveryRequestsCapabilitiesWithoutModelOrUserShellText() async throws {
        let http = FixtureHTTP { request in
            let rpc = try JSONValue.parse(request.httpBody!)
            let result: JSONValue = rpc["method"].string == "initialize" ? ["protocolVersion": "2025-03-26"] : ["content": [["type": "text", "text": .string(capabilityFixture().text())]]]
            return (try JSONValue.object(["jsonrpc": "2.0", "id": rpc["id"], "result": result]).data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await DesktopHelperProbe.check(deviceID: "selected-fixture-pc", path: "", tools: [commandSchema], mcp: MCPClient(http: http), token: "fixture-token")
        XCTAssertEqual(result.path, fixturePath)
        let requests = await http.requests
        let call = try JSONValue.parse(requests.last!.httpBody!)
        XCTAssertEqual(call["params"]["name"], "start_process")
        let args = call["params"]["arguments"]
        XCTAssertEqual(args["deviceId"], "selected-fixture-pc"); XCTAssertEqual(args["timeout_ms"], 3000)
        let encoded = args["command"].string!.components(separatedBy: "-EncodedCommand ").last!
        let script = String(data: Data(base64Encoded: encoded)!, encoding: .utf16LittleEndian)!
        XCTAssertTrue(script.contains("GetFolderPath('LocalApplicationData')")); XCTAssertFalse(script.contains("fixture-token"))
        let b64 = script.components(separatedBy: "-PayloadB64 '")[1].components(separatedBy: "'")[0]
        let payload = try JSONValue.parse(Data(base64Encoded: b64)!)
        XCTAssertEqual(payload["operation"], "capabilities"); XCTAssertEqual(payload["arguments"], [:]); XCTAssertEqual(payload["roots"], [])
    }
    func testUnknownSchemaIsRejectedBeforeAnyRequest() async {
        let http = FixtureHTTP { _ in XCTFail("Invalid schema dispatched"); throw BBError.invalid("Fixture must not run") }
        var schema = commandSchema.object!; schema["inputSchema"] = ["properties": ["command": ["type": "string"]]]
        do { _ = try await DesktopHelperProbe.check(deviceID: "pc", path: "", tools: [.object(schema)], mcp: MCPClient(http: http), token: "fixture"); XCTFail("Missing device binding accepted") } catch {}
        let requests = await http.requests; XCTAssertTrue(requests.isEmpty)
    }
}

/// Holds a probe past cancellation to exercise actual stale-reply boundaries.
@MainActor private final class HeldHelperFixture {
    let began: XCTestExpectation
    var calls = 0
    var continuation: CheckedContinuation<HelperVerification, Error>?
    init(_ began: XCTestExpectation) { self.began = began }
    func run() async throws -> HelperVerification {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; began.fulfill() }
    }
    func release() { let c = continuation; continuation = nil; c?.resume(returning: HelperVerification(path: fixturePath)) }
}

@MainActor final class DesktopHelperControllerTests: XCTestCase {
    func testConcurrentForegroundAndSendShareOneProbeAndPublishBeforeReturn() async throws {
        let fixture = HeldHelperFixture(expectation(description: "Probe began")), controller = DesktopHelperController()
        var savedPath = ""
        controller.onChange = { if $0.phase == .ready { savedPath = $0.path } }
        let first = Task { try await controller.check(deviceID: "pc", path: "") { try await fixture.run() } }
        await fulfillment(of: [fixture.began], timeout: 2)
        let joined = expectation(description: "Second waiter joined")
        let second = Task { joined.fulfill(); return try await controller.check(deviceID: "pc", path: "") { XCTFail("Duplicate check"); return HelperVerification(path: "wrong") } }
        await fulfillment(of: [joined], timeout: 2)
        fixture.release()
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a, b); XCTAssertEqual(fixture.calls, 1); XCTAssertEqual(savedPath, fixturePath)
        XCTAssertEqual(controller.snapshot.phase, .ready); XCTAssertEqual(controller.snapshot.deviceID, "pc")
    }
    func testDeadlineEndsCallerEvenWhenProbeIgnoresCancellation() async throws {
        let fixture = HeldHelperFixture(expectation(description: "Probe began")), controller = DesktopHelperController()
        let task = Task { try await controller.check(deviceID: "pc", path: "", timeoutNanoseconds: 40_000_000) { try await fixture.run() } }
        await fulfillment(of: [fixture.began], timeout: 2)
        do { _ = try await task.value; XCTFail("Deadline did not fail") } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        let state = controller.snapshot
        XCTAssertEqual(state.phase, .failed); fixture.release()
        await Task.yield(); XCTAssertEqual(controller.snapshot, state)
    }
    func testBackgroundInvalidatesProofAndOldReplyCannotReplaceNewDevice() async throws {
        let fixture = HeldHelperFixture(expectation(description: "Old probe began")), controller = DesktopHelperController()
        let old = Task { try await controller.check(deviceID: "old", path: "") { try await fixture.run() } }
        await fulfillment(of: [fixture.began], timeout: 2)
        controller.invalidate()
        do { _ = try await old.value; XCTFail("Invalidated check completed") } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await controller.check(deviceID: "new", path: "C:\\New\\BlackBoxHelper.ps1") { HelperVerification(path: "C:\\New\\BlackBoxHelper.ps1") }
        let state = controller.snapshot; fixture.release(); await Task.yield()
        XCTAssertEqual(controller.snapshot, state); XCTAssertEqual(state.deviceID, "new")
        controller.invalidate(); XCTAssertEqual(controller.snapshot.phase, .idle)
    }
    func testFailedCheckCanBeRetriedWithoutChangingDevice() async throws {
        let controller = DesktopHelperController()
        do { _ = try await controller.check(deviceID: "pc", path: "") { throw BBError.setup("Fixture unavailable") }; XCTFail() } catch {}
        XCTAssertEqual(controller.snapshot.phase, .failed)
        _ = try await controller.check(deviceID: "pc", path: "") { HelperVerification(path: fixturePath) }
        XCTAssertEqual(controller.snapshot.phase, .ready)
    }
}

@MainActor final class DesktopConversationTests: XCTestCase {
    private func reply(_ text: String = "", calls: [JSONValue] = []) -> ModelReply {
        var parts = calls.map { JSONValue.object(["functionCall": $0]) }
        if !text.isEmpty { parts.append(["text": .string(text)]) }
        return ModelReply(content: ["role": "model", "parts": .array(parts)], text: text, sources: [], attributionHTML: [], grounding: [:], tokens: 5)
    }
    func testSuccessfulPreflightExposesAndDispatchesResourceToolOnPinnedPC() async throws {
        let controller = DesktopHelperController(), store = try Repository(path: ":memory:")
        let task = try store.commit(input: "Check my RAM again", deviceID: "pc")
        let checked = try await controller.check(deviceID: "pc", path: "") { try DesktopHelperProbe.evaluate(capabilityFixture(), configuredPath: "") }
        let policy = ToolPolicy(device: PCDevice(id: "pc", name: "Fixture", online: true), aliases: [], helperVerified: controller.snapshot.phase == .ready)
        let executor = FixtureExecutor(), model = ScriptedModel([reply(calls: [["name": "inspect_resources", "id": "ram", "args": [:]]]), reply("Measured fixture result.")])
        let engine = ConversationEngine(store: store, model: model, executor: executor, policy: policy, settings: AppSettings())
        _ = try await engine.run(taskID: task.id, onText: { _ in }, onChange: {}, review: { _ in true })
        XCTAssertEqual(checked.path, fixturePath); XCTAssertEqual(executor.calls.count, 1); XCTAssertEqual(executor.calls.first?.deviceID, "pc")
        let tools = await model.toolLists, systems = await model.systems
        XCTAssertTrue(tools[0].contains { $0["name"] == "inspect_resources" })
        XCTAssertTrue(systems[0].contains("Ready; use the declared desktop tools")); XCTAssertTrue(systems[0].contains("overrides older conversation claims"))
        XCTAssertTrue(systems[0].contains("port 3389 is not a prerequisite"))
    }
    func testUnavailableHelperExplainsSetupAndCannotDispatchDesktopCall() async throws {
        let store = try Repository(path: ":memory:"), executor = FixtureExecutor()
        let task = try store.commit(input: "Check again", deviceID: "pc")
        let model = ScriptedModel([reply(calls: [["name": "inspect_resources", "id": "ram", "args": [:]]]), reply("Check the Windows helper in Settings.")])
        let policy = ToolPolicy(device: PCDevice(id: "pc", name: "Fixture", online: true), aliases: [], helperVerified: false)
        let engine = ConversationEngine(store: store, model: model, executor: executor, policy: policy, settings: AppSettings(), connectionStatus: "Fixture helper timed out; use Settings.")
        _ = try await engine.run(taskID: task.id, onText: { _ in }, onChange: {}, review: { _ in true })
        let tools = await model.toolLists, systems = await model.systems
        XCTAssertEqual(tools[0].compactMap { $0["name"].string }, ["research_web"])
        XCTAssertTrue(systems[0].contains("Fixture helper timed out; use Settings.")); XCTAssertTrue(executor.calls.isEmpty)
        XCTAssertTrue(try store.all(ActionRecord.self, kind: "action").isEmpty)
        XCTAssertFalse(try store.task(task.id).detail.contains("observed tool results"))
    }
    func testOrdinaryReplyNeverRecordsObservedDesktopResults() async throws {
        let store = try Repository(path: ":memory:"), task = try store.commit(input: "Hello", deviceID: nil)
        let engine = ConversationEngine(store: store, model: ScriptedModel([reply("Hello.")]), executor: FixtureExecutor(), policy: ToolPolicy(device: nil, aliases: [], helperVerified: false), settings: AppSettings())
        _ = try await engine.run(taskID: task.id, onText: { _ in }, onChange: {}, review: { _ in true })
        XCTAssertEqual(try store.task(task.id).state, .completed)
        XCTAssertTrue(try store.task(task.id).detail.contains("0 tool call(s) recorded"))
    }
}
