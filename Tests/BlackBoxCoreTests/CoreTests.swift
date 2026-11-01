import XCTest
@testable import BlackBoxCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor FixtureHTTP: HTTPClient {
    var requests: [URLRequest] = []
    let respond: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    init(respond: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) { self.respond = respond }
    func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { requests.append(request); return try respond(request) }
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        let (data, _) = try await self.data(request)
        return AsyncThrowingStream { c in for byte in data { c.yield(Data([byte])) }; c.finish() }
    }
}
actor ScriptedModel: ReasoningClient {
    var replies: [ModelReply]
    var histories: [[JSONValue]] = []
    var systems: [String] = []
    var toolLists: [[JSONValue]] = []
    init(_ replies: [ModelReply]) { self.replies = replies }
    func generate(history: [JSONValue], system: String, tools: [JSONValue], grounded: Bool, onText: @escaping @Sendable (String) async -> Void) async throws -> ModelReply {
        histories.append(history); systems.append(system); toolLists.append(tools)
        guard !replies.isEmpty else { throw BBError.wire("Fixture exhausted") }; return replies.removeFirst()
    }
}
@MainActor final class FixtureExecutor: ToolExecutor {
    var calls: [ValidatedTool] = []
    var error: Error?
    var before: (() throws -> Void)?
    var outcome = ToolOutcome(value: ["accepted": true, "evidenceScope": "fixture only"])
    func execute(_ tool: ValidatedTool) async throws -> ToolOutcome {
        calls.append(tool); try before?(); if let error { throw error }; return outcome
    }
}

final class ProtocolTests: XCTestCase {
    func testCredentialExcerptsAreRedacted() {
        let input = "Useful document. api_key=fixture-long-secret-value and Bearer fixture-long-access-value"
        let output = ContentRedactor.clean(input)
        XCTAssertTrue(output.contains("Useful document.")); XCTAssertFalse(output.contains("fixture-long-secret-value")); XCTAssertFalse(output.contains("fixture-long-access-value"))
        XCTAssertEqual(ContentRedactor.clean("-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"), "[credential redacted]")
    }
    func testSSESplitUTF8AndCRLF() throws {
        var parser = SSEParser(); var result: [Data] = []
        for b in Data(":comment\r\ndata: héllo\r\ndata: world\r\n\r\n".utf8) { result += try parser.feed(Data([b])) }
        XCTAssertEqual(result.map { String(decoding: $0, as: UTF8.self) }, ["héllo\nworld"]); try parser.finish()
    }
    func testSSETruncationAndSize() throws {
        var p = SSEParser(); _ = try p.feed(Data("data: {}".utf8)); XCTAssertThrowsError(try p.finish())
        var huge = SSEParser(); XCTAssertThrowsError(try huge.feed(Data(repeating: 1, count: 1_048_576)))
    }
    func testOpaqueJSONRoundTrip() throws {
        let original: JSONValue = ["thoughtSignature": "opaque+==", "future": ["v": [1, true, .null]], "functionCall": ["id": "abc", "name": "open_url", "args": ["url": "https://youtube.com"]]]
        XCTAssertEqual(try JSONValue.parse(original.data()), original)
    }
    func testPCMByteBoundaries() throws {
        var d = PCM16Decoder(); XCTAssertEqual(d.decode(Data([0])), []); XCTAssertEqual(d.decode(Data([128, 255, 127])), [-1, Float(32767)/32768]); try d.finish()
        _ = d.decode(Data([1])); XCTAssertThrowsError(try d.finish())
    }
    func testCallbackStateAndDuplicates() throws {
        XCTAssertEqual(try OAuthClient.code(from: URL(string: "com.kellen.blackbox:/oauth/callback?code=abc&state=s")!, expectedState: "s"), "abc")
        for v in ["com.kellen.blackbox:/oauth/callback?code=abc&state=x", "com.kellen.blackbox:/oauth/callback?code=a&state=s&state=s", "other:/oauth/callback?code=a&state=s", "com.kellen.blackbox://evil/oauth/callback?code=a&state=s"] { XCTAssertThrowsError(try OAuthClient.code(from: URL(string: v)!, expectedState: "s")) }
    }
    func testFormEscapesValues() {
        XCTAssertEqual(String(decoding: OAuthClient.form(["token": "a+b&=\n"]), as: UTF8.self), "token=a%2Bb%26%3D%0A")
    }
    func testOAuthHostValidation() throws {
        _ = try OAuthClient.trusted("https://mcp.desktopcommander.app/token")
        for u in ["http://mcp.desktopcommander.app", "https://evil.com", "https://user:pass@mcp.desktopcommander.app/token"] { XCTAssertThrowsError(try OAuthClient.trusted(u)) }
    }
    func testUnsupportedRegistrationMethodRejected() async throws {
        let http = FixtureHTTP { request in
            let d: JSONValue = ["client_id": "fixture", "token_endpoint_auth_method": "private_key_jwt", "redirect_uris": [.string(OAuthClient.callback)]]
            return (try d.data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
        let d = OAuthDiscovery(resource: "https://mcp.desktopcommander.app", issuer: "https://mcp.desktopcommander.app", authorizationEndpoint: "https://mcp.desktopcommander.app/authorize", tokenEndpoint: "https://mcp.desktopcommander.app/token", registrationEndpoint: "https://mcp.desktopcommander.app/register", revocationEndpoint: nil, scopes: ["mcp:tools"])
        do { _ = try await OAuthClient(http: http).register(d); XCTFail("Unsupported method accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("unsupported")) }
    }
    func testRefreshAudienceAndRotationFallback() async throws {
        let http = FixtureHTTP { request in
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            XCTAssertTrue(body.contains("grant_type=refresh_token")); XCTAssertTrue(body.contains("resource=https%3A%2F%2Fmcp.desktopcommander.app")); XCTAssertFalse(body.contains("client_secret"))
            let d: JSONValue = ["access_token": "fixture-access", "token_type": "Bearer", "expires_in": 3600]
            return (try d.data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let d = OAuthDiscovery(resource: "https://mcp.desktopcommander.app", issuer: "https://mcp.desktopcommander.app", authorizationEndpoint: "https://mcp.desktopcommander.app/authorize", tokenEndpoint: "https://mcp.desktopcommander.app/token", registrationEndpoint: nil, revocationEndpoint: nil, scopes: ["mcp:tools"])
        let token = try await OAuthClient(http: http).token(d, registration: OAuthRegistration(clientID: "fixture-client"), refresh: "fixture-refresh")
        XCTAssertEqual(token.refreshToken, "fixture-refresh"); XCTAssertGreaterThan(token.expiry.timeIntervalSinceNow, 3500)
        do { try await OAuthClient(http: http).revoke(d, registration: OAuthRegistration(clientID: "fixture-client"), tokens: token); XCTFail("Invented revocation endpoint") } catch { XCTAssertTrue(error.localizedDescription.contains("no revocation endpoint")) }
    }
    func testMCPDeviceAdapterFailsClosed() throws {
        XCTAssertEqual(try MCPClient.devices(["devices": [["id": "one", "name": "PC", "status": "online"]]]), [PCDevice(id: "one", name: "PC", online: true)])
        XCTAssertEqual(try MCPClient.devices(["devices": []]), [])
        XCTAssertThrowsError(try MCPClient.devices(["text": "one PC probably online"]))
        XCTAssertThrowsError(try MCPClient.devices(["devices": [["id": "one", "name": "PC"]]]))
    }
    func testMCPErrorNotSuccess() { XCTAssertThrowsError(try MCPClient.payload(["isError": true, "content": []])) }
    func testHelperCompletionRequiresStructuredEvidence() {
        XCTAssertNil(HelperEvidence.parse(["text": "Process started, still running"], operation: "open_url"))
        XCTAssertNil(HelperEvidence.parse(["text": "BLACKBOX_HELPER_V1 Windows PowerShell"], operation: "capabilities"))
        let evidence: JSONValue = ["marker": "BLACKBOX_HELPER_V1", "operation": "open_url", "ok": true, "accepted": true]
        XCTAssertEqual(HelperEvidence.parse(["output": .string("Initial output:\n" + evidence.text())], operation: "open_url"), evidence)
        XCTAssertNil(HelperEvidence.parse(evidence, operation: "move_file"))
    }
    func testMCPCorrelationFailure() async throws {
        let http = FixtureHTTP { r in (try JSONValue.object(["jsonrpc": "2.0", "id": "wrong", "result": [:]]).data(), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!) }
        do { try await MCPClient(http: http).initialize(token: "fixture"); XCTFail("Mismatched ID accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("ID mismatch")) }
        let count = await http.requests.count; XCTAssertEqual(count, 1)
    }
    func testGeminiStreamingPreservesSignaturesAndCallID() async throws {
        let p: JSONValue = ["functionCall": ["name": "open_url", "id": "call-7", "args": ["url": "https://youtube.com"]], "thoughtSignature": "opaque", "futureField": "keep"]
        let event: JSONValue = ["candidates": [["content": ["role": "model", "parts": .array([p])], "finishReason": "STOP"]], "usageMetadata": ["totalTokenCount": 17]]
        let http = FixtureHTTP { r in (Data("data: \(event.text())\n\n".utf8), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!) }
        let result = try await GeminiClient(key: "fixture", model: "configured-model", http: http).generate(history: [], system: "", tools: [], grounded: false, onText: { _ in })
        XCTAssertEqual(result.content["parts"].array, [p]); XCTAssertEqual(result.calls.first?["id"].string, "call-7"); XCTAssertEqual(result.tokens, 17)
        let request = await http.requests.first!
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture"); XCTAssertFalse(request.url!.absoluteString.contains("fixture"))
    }
    func testIncompleteGeminiCannotDispatch() async throws {
        let event: JSONValue = ["candidates": [["content": ["parts": [["functionCall": ["name": "open_url", "args": [:]]]]], "finishReason": "MAX_TOKENS"]]]
        let http = FixtureHTTP { r in (Data("data: \(event.text())\n\n".utf8), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!) }
        do { _ = try await GeminiClient(key: "fixture", model: "m", http: http).generate(history: [], system: "", tools: [], grounded: false, onText: { _ in }); XCTFail("Truncated tool accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("incomplete")) }
    }
    func testCitationsUseUTF8Offsets() {
        let g: JSONValue = ["groundingChunks": [["web": ["title": "Source", "uri": "https://example.com"]]], "groundingSupports": [["segment": ["endIndex": 3], "groundingChunkIndices": [0]]]]
        XCTAssertEqual(GeminiClient.citedText("hé", grounding: g), "hé [1](https://example.com)")
    }
}

final class PolicyTests: XCTestCase {
    let device = PCDevice(id: "pc-1", name: "Windows", online: true)
    var policy: ToolPolicy { ToolPolicy(device: device, aliases: [FolderAlias(deviceID: "pc-1", name: "projects", path: "C:\\Work")], helperVerified: true) }
    func testDeviceAndAliasBinding() throws {
        let t = try policy.validate(name: "open_alias", arguments: ["alias": "projects"])
        XCTAssertEqual(t.deviceID, "pc-1"); XCTAssertEqual(t.arguments["path"], "C:\\Work")
    }
    func testRejectsUnexpectedShellDeviceAndExtraArgs() {
        for (name, args): (String, JSONValue) in [("shell", ["command": "format C:"]), ("open_url", ["url": "https://youtube.com", "deviceId": "pc-2"]), ("inspect_resources", ["x": "a"])] { XCTAssertThrowsError(try policy.validate(name: name, arguments: args)) }
    }
    func testPathTraversalAndCredentials() {
        for p in ["C:\\Work\\..\\secret.txt", "C:\\Work2\\secret.txt", "C:\\Work\\a.txt:stream", "\\\\server\\share\\a.txt", "C:\\Work\\.env", "C:\\Work\\key.pem", "C:\\Work\\.ssh\\config", "C:\\Work\\trailing.\\a.txt"] { XCTAssertThrowsError(try policy.validate(name: "read_file", arguments: ["path": .string(p)]), p) }
    }
    func testURLAndApplicationAllowlist() {
        for u in ["file:///C:/Windows", "javascript:alert(1)", "https://secret@example.com", "ms-settings:"] { XCTAssertThrowsError(try policy.validate(name: "open_url", arguments: ["url": .string(u)])) }
        XCTAssertThrowsError(try policy.validate(name: "open_application", arguments: ["application": "powershell"]))
    }
    func testOfflineDoesNotBlockPublicResearch() throws {
        let p = ToolPolicy(device: nil, aliases: [], helperVerified: false)
        XCTAssertEqual(p.declarations.count, 1); XCTAssertNil(try p.validate(name: "research_web", arguments: ["query": "two parts"]).deviceID)
        XCTAssertThrowsError(try p.validate(name: "open_url", arguments: ["url": "https://youtube.com"]))
    }
    func testHelperGateAndReview() throws {
        let p = ToolPolicy(device: device, aliases: [], helperVerified: false)
        XCTAssertThrowsError(try p.validate(name: "open_url", arguments: ["url": "https://youtube.com"]))
        XCTAssertTrue(try policy.validate(name: "move_file", arguments: ["source": "C:\\Work\\a.txt", "destination": "C:\\Work\\b.txt"]).needsReview)
    }
    func testHelperEncodesDataNotCode() throws {
        let cmd = try HelperCommand.make(path: "C:\\Tools\\BlackBoxHelper.ps1", operation: "open_url", arguments: ["url": "https://example.com/?q=$(calc)&a='b'"], roots: [])
        XCTAssertFalse(cmd.contains("$(calc)")); XCTAssertFalse(cmd.contains("example.com"))
        let script = String(data: Data(base64Encoded: cmd.split(separator: " ").last!.description)!, encoding: .utf16LittleEndian)!
        XCTAssertTrue(script.hasPrefix("& 'C:\\Tools\\BlackBoxHelper.ps1' -PayloadB64 '")); XCTAssertFalse(script.contains("$(calc)"))
    }
}

@MainActor final class ExecutionTests: XCTestCase {
    func reply(calls: [JSONValue] = [], text: String = "") -> ModelReply {
        ModelReply(content: ["role": "model", "parts": calls.isEmpty ? [["text": .string(text)]] : .array(calls.map { ["functionCall": $0, "thoughtSignature": "keep"] })], text: text, sources: [], attributionHTML: [], grounding: [:], tokens: 10)
    }
    var call: JSONValue { ["name": "open_url", "id": "one", "args": ["url": "https://youtube.com"]] }
    func engine(_ store: Repository, _ model: ScriptedModel, _ exec: FixtureExecutor) -> ConversationEngine {
        ConversationEngine(store: store, model: model, executor: exec,
                           policy: ToolPolicy(device: PCDevice(id: "pc", name: "PC", online: true), aliases: [], helperVerified: true), settings: AppSettings())
    }
    func testVerticalSliceWithFixtures() async throws {
        let store = try Repository(path: ":memory:"); let t = try store.commit(input: "Open YouTube", deviceID: "pc")
        let model = ScriptedModel([reply(calls: [call]), reply(text: "Launch request accepted; page load not observed.")]); let exec = FixtureExecutor()
        exec.before = { XCTAssertEqual(try store.all(ActionRecord.self, kind: "action").count, 1) }
        let answer = try await engine(store, model, exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true })
        XCTAssertTrue(answer.text.contains("not observed")); XCTAssertEqual(exec.calls.count, 1)
        XCTAssertEqual(try store.task(t.id).state, .completed)
        let histories = await model.histories
        XCTAssertEqual(histories[1][1]["parts"].array[0]["thoughtSignature"], "keep")
        XCTAssertEqual(histories[1][2]["parts"].array[0]["functionResponse"]["id"], "one")
    }
    func testDuplicateDispatchPreventedEvenWithNewCallID() async throws {
        let store = try Repository(path: ":memory:"); let t = try store.commit(input: "Open", deviceID: "pc")
        var second = call.object!; second["id"] = "two"
        let model = ScriptedModel([reply(calls: [call, .object(second)]), reply(text: "Duplicate prevented")]); let exec = FixtureExecutor()
        _ = try await engine(store, model, exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true })
        XCTAssertEqual(exec.calls.count, 1)
    }
    func testTimeoutRemainsUnknownAndIsNeverRetried() async throws {
        let store = try Repository(path: ":memory:"); let t = try store.commit(input: "Open", deviceID: "pc")
        let exec = FixtureExecutor(); exec.error = URLError(.timedOut)
        do { _ = try await engine(store, ScriptedModel([reply(calls: [call])]), exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true }); XCTFail() } catch {}
        XCTAssertEqual(exec.calls.count, 1); XCTAssertEqual(try store.task(t.id).state, .unknown)
        XCTAssertEqual(try store.all(ActionRecord.self, kind: "action").first?.state, .unknown)
        do { _ = try await engine(store, ScriptedModel([]), exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true }); XCTFail() } catch {}
        XCTAssertEqual(exec.calls.count, 1)
    }
    func testCancellationPreventsNextParallelAction() async throws {
        let store = try Repository(path: ":memory:"); let t = try store.commit(input: "Open", deviceID: "pc")
        let exec = FixtureExecutor(); exec.before = { try store.cancel(t.id) }
        var other = call.object!; other["args"] = ["url": "https://example.com"]; other["id"] = "two"
        do { _ = try await engine(store, ScriptedModel([reply(calls: [call, .object(other)])]), exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true }); XCTFail() } catch {}
        XCTAssertEqual(exec.calls.count, 1); XCTAssertEqual(try store.task(t.id).state, .cancelled)
    }
    func testCrashRecoveryPersistsAndNeverRequeues() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { for p in [file, file + "-wal", file + "-shm"] { try? FileManager.default.removeItem(atPath: p) } }
        let store = try Repository(path: file); let t = try store.commit(input: "Open", deviceID: "pc"); try store.state(t.id, .running, detail: "dispatch")
        let a = ActionRecord(id: "a", taskID: t.id, functionID: "one", name: "open_url", arguments: ["url": "https://youtube.com"], deviceID: "pc", state: .running, date: Date())
        try store.claim(a)
        let reopened = try Repository(path: file); try reopened.recover()
        XCTAssertEqual(try reopened.task(t.id).state, .unknown); XCTAssertEqual(try reopened.all(ActionRecord.self, kind: "action").first?.state, .unknown)
    }
    func testQueuedRecoveryBlocked() async throws {
        let s = try Repository(path: ":memory:"); let t = try s.commit(input: "Do later", deviceID: "pc"); try s.recover(); XCTAssertEqual(try s.task(t.id).state, .blocked)
    }
    func testCancelledTaskCannotClaim() async throws {
        let s = try Repository(path: ":memory:"); let t = try s.commit(input: "Open", deviceID: "pc"); try s.cancel(t.id)
        let a = ActionRecord(id: "a", taskID: t.id, functionID: "one", name: "open_url", arguments: [:], deviceID: "pc", state: .running, date: Date())
        XCTAssertThrowsError(try s.claim(a)); XCTAssertTrue(try s.all(ActionRecord.self, kind: "action").isEmpty)
    }
    func testKnownToolFailureIsCorrelatedBackToModel() async throws {
        let s = try Repository(path: ":memory:"); let t = try s.commit(input: "Open", deviceID: "pc")
        let exec = FixtureExecutor(); exec.outcome = ToolOutcome(value: ["error": "Launch rejected", "executed": false], succeeded: false)
        let model = ScriptedModel([reply(calls: [call]), reply(text: "Windows rejected the launch.")])
        _ = try await engine(s, model, exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true })
        XCTAssertEqual(try s.all(ActionRecord.self, kind: "action").first?.state, .failed)
        let histories = await model.histories
        XCTAssertEqual(histories[1].last?["parts"].array.first?["functionResponse"]["response"]["executed"], false)
    }
    func testInvalidToolReturnsErrorWithoutDispatch() async throws {
        let s = try Repository(path: ":memory:"); let t = try s.commit(input: "Do it", deviceID: "pc")
        let exec = FixtureExecutor(); let bad: JSONValue = ["name": "shell", "id": "bad", "args": ["command": "unsafe"]]
        let model = ScriptedModel([reply(calls: [bad]), reply(text: "That tool is unavailable.")])
        _ = try await engine(s, model, exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true })
        XCTAssertTrue(exec.calls.isEmpty); XCTAssertTrue(try s.all(ActionRecord.self, kind: "action").isEmpty)
    }
    func testPostClaimSetupFailureStopsTask() async throws {
        let s = try Repository(path: ":memory:"); let t = try s.commit(input: "Open", deviceID: "pc")
        let exec = FixtureExecutor(); exec.error = BBError.setup("Lost connection during dispatch")
        var other = call.object!; other["id"] = "two"; other["args"] = ["url": "https://example.com"]
        do { _ = try await engine(s, ScriptedModel([reply(calls: [call, .object(other)])]), exec).run(taskID: t.id, onText: { _ in }, onChange: {}, review: { _ in true }); XCTFail() } catch {}
        XCTAssertEqual(exec.calls.count, 1); XCTAssertEqual(try s.task(t.id).state, .unknown)
    }
}
