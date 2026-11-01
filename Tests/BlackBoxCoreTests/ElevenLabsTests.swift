import XCTest
@testable import BlackBoxCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let fixtureVoiceID = "FixtureVoiceABC123"
private func elevenModelsFixture() -> JSONValue {
    [["model_id": "eleven_v4", "name": "Eleven v4", "can_do_text_to_speech": true],
     ["model_id": "eleven_flash_v2_5", "name": "Eleven Flash v2.5", "can_do_text_to_speech": true],
     ["model_id": "scribe_fixture", "name": "Not a speech synthesis model", "can_do_text_to_speech": false]]
}
private func elevenResponse(_ request: URLRequest, value: JSONValue, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    (try value.data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
}
private func elevenMetadataFixture() -> FixtureHTTP {
    FixtureHTTP { request in
        if request.url!.path == "/v1/models" { return try elevenResponse(request, value: elevenModelsFixture()) }
        return try elevenResponse(request, value: ["voice_id": .string(request.url!.lastPathComponent), "name": "Fixture voice"])
    }
}
/// Lets an old voice lookup complete after timeout, key replacement or voice editing.
private actor SuspendedElevenHTTPFixture: HTTPClient {
    private var request: URLRequest?
    private var pending: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    let began: @Sendable () -> Void
    init(began: @escaping @Sendable () -> Void) { self.began = began }
    func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url!.path == "/v1/models" { return try elevenResponse(request, value: elevenModelsFixture()) }
        self.request = request
        return try await withCheckedThrowingContinuation { pending = $0; began() }
    }
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> { throw BBError.setup("Fixture only supports metadata") }
    func finish() throws {
        guard let request, let pending else { throw BBError.setup("Fixture was not started") }
        self.pending = nil
        pending.resume(returning: try elevenResponse(request, value: ["voice_id": .string(request.url!.lastPathComponent), "name": "Old fixture voice"]))
    }
}

final class ElevenLabsClientTests: XCTestCase {
    func testDisplayNamesNormalizeToDocumentedModelIDs() {
        for label in ["ElevenV4", "Eleven v4", " ELEVEN_V4\n", "eleven-v4"] {
            XCTAssertEqual(ElevenLabsClient.normalizedModelID(label), "eleven_v4")
        }
        XCTAssertEqual(ElevenLabsClient.normalizedModelID("Eleven v4 Turbo"), "eleven_v4_turbo")
        XCTAssertEqual(ElevenLabsClient.normalizedModelID("Eleven Flash v2.5"), "eleven_flash_v2_5")
        XCTAssertEqual(ElevenLabsClient.normalizedModelID("future_exact_model_ID"), "future_exact_model_ID", "An unknown ID was silently replaced")
    }
    func testSpeechRequestUsesCanonicalModelPCMAndHeaderAuthentication() async throws {
        let http = FixtureHTTP { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url!.path, "/v1/text-to-speech/" + fixtureVoiceID + "/stream")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "output_format", value: "pcm_24000")])
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "fixture-secret")
            XCTAssertFalse(request.url!.absoluteString.contains("fixture-secret"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Accept"))
            let body = try JSONValue.parse(request.httpBody!)
            XCTAssertEqual(body["model_id"].string, "eleven_v4"); XCTAssertEqual(body["text"].string, "Test speech")
            return (Data([0, 0, 255, 127]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/pcm"])!)
        }
        let client = ElevenLabsClient(key: " fixture-secret \n", voiceID: " " + fixtureVoiceID + "\n", model: "ElevenV4", http: http)
        let stream = try await client.audio(text: "Test speech")
        var data = Data(); for try await chunk in stream { data.append(chunk) }
        XCTAssertEqual(data, Data([0, 0, 255, 127]))
        let requests = await http.requests; XCTAssertEqual(requests.count, 1, "Speech must not depend on a metadata permission")
    }
    func testMetadataUsesReadEndpointsAndNeverGeneratesSpeech() async throws {
        let http = elevenMetadataFixture()
        try await ElevenLabsClient(key: "fixture", voiceID: fixtureVoiceID, model: "ElevenV4", http: http).validate()
        let requests = await http.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/models", "/v1/voices/" + fixtureVoiceID])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    }
    func testModelCatalogExcludesNonTTSModelsAndRejectsBadShape() async throws {
        let client = ElevenLabsClient(key: "fixture", voiceID: fixtureVoiceID, model: "m", http: elevenMetadataFixture())
        let models = try await client.availableModels()
        XCTAssertEqual(Set(models.map(\.id)), Set(["eleven_v4", "eleven_flash_v2_5"]))
        let bad = FixtureHTTP { try elevenResponse($0, value: ["models": []]) }
        do { _ = try await ElevenLabsClient(key: "fixture", voiceID: fixtureVoiceID, model: "m", http: bad).availableModels(); XCTFail("Wrong response shape accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unreadable")) }
    }
    func testVoiceMetadataMustMatchRequestedVoice() async throws {
        let http = FixtureHTTP { try elevenResponse($0, value: ["voice_id": "different-fixture-voice", "name": "Wrong voice"]) }
        do { _ = try await ElevenLabsClient(key: "fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: http).voiceInfo(); XCTFail("Wrong voice accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("selected voice")) }
    }
    func testEmptyTextAndInvalidVoiceCannotConsumeSpeechQuota() async throws {
        let http = elevenMetadataFixture()
        for (id, text) in [(fixtureVoiceID, " \n"), ("https://example.com/voice", "Hello")] {
            do { _ = try await ElevenLabsClient(key: "fixture", voiceID: id, model: "eleven_v4", http: http).audio(text: text); XCTFail("Invalid speech request dispatched") } catch {}
        }
        let requests = await http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testErrorKeepsProviderReasonAndRemovesEchoedKey() throws {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices/FixtureVoice")!)
        request.setValue("fixture-secret-key", forHTTPHeaderField: "xi-api-key")
        let body: JSONValue = ["detail": ["status": "missing_permissions", "message": "Missing voices_read for fixture-secret-key"]]
        let error = ElevenLabsAPIError(data: try body.data(), statusCode: 400, request: request)
        XCTAssertEqual(error.operation, "Voice check"); XCTAssertEqual(error.reason, "missing_permissions")
        XCTAssertTrue(error.localizedDescription.contains("HTTP 400")); XCTAssertTrue(error.localizedDescription.contains("voices_read"))
        XCTAssertFalse(error.localizedDescription.contains("fixture-secret-key")); XCTAssertTrue(error.detail.contains("[key redacted]"))
    }
    func testStringAndValidationListErrorsAreReadable() throws {
        let request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/FixtureVoice/stream")!)
        let stringError = ElevenLabsAPIError(data: try JSONValue.object(["detail": "Voice is still processing"]).data(), statusCode: 400, request: request)
        XCTAssertTrue(stringError.localizedDescription.contains("Voice is still processing")); XCTAssertEqual(stringError.operation, "Speech request")
        let listError = ElevenLabsAPIError(data: try JSONValue.object(["detail": [["msg": "Unknown model_id"]]]).data(), statusCode: 422, request: request)
        XCTAssertTrue(listError.localizedDescription.contains("Unknown model_id"))
        let html = ElevenLabsAPIError(data: Data("<html>Not JSON</html>".utf8), statusCode: 503, request: request)
        XCTAssertTrue(html.localizedDescription.contains("temporarily")); XCTAssertFalse(html.localizedDescription.contains("<html>"))
    }
    func testReadScopeFailureDoesNotBlockSpeechOnlyKeys() async throws {
        let http = FixtureHTTP { request in
            if request.httpMethod == "POST" { return (Data([0, 0]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
            return try elevenResponse(request, value: ["detail": ["status": "missing_permissions", "message": "Missing models_read"]], status: 401)
        }
        let client = ElevenLabsClient(key: "fixture", voiceID: fixtureVoiceID, model: "ElevenV4", http: http)
        do { try await client.validate(); XCTFail("Read scope ignored") } catch { XCTAssertTrue(error.localizedDescription.contains("models_read")) }
        let stream = try await client.audio(text: "Hello")
        var count = 0; for try await chunk in stream { count += chunk.count }
        XCTAssertEqual(count, 2)
    }
}

@MainActor final class ElevenLabsValidationTests: XCTestCase {
    func testSuccessfulMetadataCheckIsNotReportedAsSpeechSuccess() async {
        let controller = ElevenValidationController()
        await controller.check(key: "fixture", voiceID: fixtureVoiceID, model: "ElevenV4", http: elevenMetadataFixture())?.value
        XCTAssertEqual(controller.snapshot.phase, .checked)
        XCTAssertTrue(controller.snapshot.message.contains("metadata")); XCTAssertTrue(controller.snapshot.message.contains("Test voice"))
    }
    func testHTTP400ShowsProviderDetailsAndKeepsModelChoices() async {
        let http = FixtureHTTP { request in
            if request.url!.path == "/v1/models" { return try elevenResponse(request, value: elevenModelsFixture()) }
            return try elevenResponse(request, value: ["detail": ["status": "voice_not_found", "message": "Voice not in this workspace"]], status: 400)
        }
        let controller = ElevenValidationController()
        await controller.check(key: "fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: http)?.value
        XCTAssertEqual(controller.snapshot.phase, .failed); XCTAssertEqual(controller.snapshot.models.count, 2)
        XCTAssertTrue(controller.snapshot.message.contains("voice_not_found")); XCTAssertTrue(controller.snapshot.message.contains("Voice not in this workspace"))
        await controller.check(key: "fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: elevenMetadataFixture())?.value
        XCTAssertEqual(controller.snapshot.phase, .checked)
    }
    func testModelChoiceUpdatesAgainstReturnedCatalog() async {
        let controller = ElevenValidationController()
        await controller.check(key: "fixture", voiceID: fixtureVoiceID, model: "unknown_fixture", http: elevenMetadataFixture())?.value
        XCTAssertEqual(controller.snapshot.phase, .chooseModel)
        controller.selectModel("ElevenV4"); XCTAssertEqual(controller.snapshot.phase, .checked)
    }
    func testDeadlineRejectsLateSuccessAndPreservesAVisibleFailure() async throws {
        let began = expectation(description: "Voice request started"), expired = expectation(description: "Deadline visible")
        let http = SuspendedElevenHTTPFixture { began.fulfill() }
        let controller = ElevenValidationController()
        controller.onChange = { if $0.phase == .failed { expired.fulfill() } }
        let task = controller.check(key: "fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: http, timeoutNanoseconds: 30_000_000)
        await fulfillment(of: [began, expired], timeout: 2)
        let state = controller.snapshot; XCTAssertFalse(state.isChecking)
        try await http.finish(); await task?.value
        XCTAssertEqual(controller.snapshot, state)
    }
    func testKeyReplacementCannotBeOverwrittenByOldVoiceResponse() async throws {
        let began = expectation(description: "Old voice request started")
        let http = SuspendedElevenHTTPFixture { began.fulfill() }
        let controller = ElevenValidationController()
        let old = controller.check(key: "old-fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: http)
        await fulfillment(of: [began], timeout: 2)
        controller.keyStored()
        await controller.check(key: "new-fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: elevenMetadataFixture())?.value
        let state = controller.snapshot
        try await http.finish(); await old?.value
        XCTAssertEqual(controller.snapshot, state)
    }
    func testWhitespaceNormalizationDoesNotCancelTheNewCheck() async throws {
        let began = expectation(description: "Voice request started")
        let http = SuspendedElevenHTTPFixture { began.fulfill() }
        let controller = ElevenValidationController()
        let task = controller.check(key: "fixture", voiceID: " " + fixtureVoiceID, model: "ElevenV4", http: http)
        await fulfillment(of: [began], timeout: 2)
        controller.voiceChanged(fixtureVoiceID + "\n")
        XCTAssertTrue(controller.snapshot.isChecking)
        try await http.finish(); await task?.value
        XCTAssertEqual(controller.snapshot.phase, .checked)
    }
    func testVoiceEditingOrKeyDeletionRejectsThePreviousResult() async throws {
        for removingKey in [false, true] {
            let began = expectation(description: "Voice request started")
            let http = SuspendedElevenHTTPFixture { began.fulfill() }
            let controller = ElevenValidationController()
            let task = controller.check(key: "fixture", voiceID: fixtureVoiceID, model: "eleven_v4", http: http)
            await fulfillment(of: [began], timeout: 2)
            if removingKey { controller.clear() } else { controller.voiceChanged("DifferentFixtureVoice") }
            let state = controller.snapshot
            try await http.finish(); await task?.value
            XCTAssertEqual(controller.snapshot, state)
        }
    }
}
