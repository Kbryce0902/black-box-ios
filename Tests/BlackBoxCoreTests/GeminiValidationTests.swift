import XCTest
@testable import BlackBoxCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deliberately ignores cancellation until the test releases the real await boundary.
private actor SuspendedGeminiHTTPFixture: HTTPClient {
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var request: URLRequest?
    let began: @Sendable () -> Void
    init(began: @escaping @Sendable () -> Void) { self.began = began }
    func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation; began()
        }
    }
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> { throw BBError.setup("Fixture is metadata only") }
    func resolve(_ value: JSONValue) throws {
        guard let continuation, let request else { throw BBError.setup("Fixture request was not started") }
        self.continuation = nil
        continuation.resume(returning: (try value.data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
    }
}

private func modelFixture(_ id: String) -> JSONValue {
    ["name": .string("models/" + id), "supportedGenerationMethods": ["generateContent"]]
}
private func catalogFixture(_ id: String) -> JSONValue { ["models": [modelFixture(id)]] }
private func immediateFixture(_ id: String) -> FixtureHTTP {
    FixtureHTTP { request in
        (try catalogFixture(id).data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class GeminiCatalogTests: XCTestCase {
    func testPaginationFiltersMethodsAndKeepsKeyOutOfURL() async throws {
        let token = "next+/&=?"
        let http = FixtureHTTP { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
            XCTAssertFalse(request.url!.absoluteString.contains("fixture-key"))
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first(where: { $0.name == "pageSize" })?.value, "1000")
            let body: JSONValue
            if query.first(where: { $0.name == "pageToken" })?.value == token {
                body = ["models": [modelFixture("gemini-first"), modelFixture("gemini-second")]]
            } else {
                body = ["models": [modelFixture("gemini-first"), ["name": "models/gemini-embedding", "supportedGenerationMethods": ["embedContent"]]], "nextPageToken": .string(token)]
            }
            return (try body.data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let models = try await GeminiClient(key: "fixture-key", model: "gemini-second", http: http).availableModels()
        XCTAssertEqual(models, ["gemini-first", "gemini-second"])
        let requests = await http.requests; XCTAssertEqual(requests.count, 2)
    }
    func testModelResourcePrefixAndWhitespaceAreAccepted() async throws {
        let http = immediateFixture("gemini-listed")
        let models = try await GeminiClient(key: " fixture-key \n", model: " models/gemini-listed \n", http: http).validate()
        XCTAssertEqual(models, ["models/gemini-listed"])
        let requests = await http.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
    }
    func testRepeatedPageTokenStopsWithoutAnInfiniteLoop() async throws {
        let http = FixtureHTTP { request in
            (try JSONValue.object(["models": [], "nextPageToken": "same"]).data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await GeminiClient(key: "fixture", model: "m", http: http).availableModels(); XCTFail("Repeated page accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("repeated")) }
        let requests = await http.requests; XCTAssertEqual(requests.count, 2)
    }
    func testMalformedCatalogIsNotMistakenForAnAcceptedKey() async throws {
        let http = FixtureHTTP { request in
            (Data(#"{"models":{"name":"unexpected"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await GeminiClient(key: "fixture", model: "m", http: http).availableModels(); XCTFail("Malformed catalog accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unreadable")) }
    }
    func testErrorBodyRetainsReasonButRedactsEchoedKey() throws {
        let key = "fixture-key-that-must-never-appear"
        let body: JSONValue = ["error": ["message": .string("Request rejected: " + key), "status": "INVALID_ARGUMENT", "details": [["reason": "API_KEY_INVALID"]]]]
        let error = GeminiAPIError(data: try body.data(), statusCode: 400, key: key)
        XCTAssertEqual(error.reason, "API_KEY_INVALID")
        XCTAssertTrue(error.localizedDescription.contains("HTTP 400"))
        XCTAssertTrue(error.localizedDescription.contains("[key redacted]"))
        XCTAssertFalse(error.localizedDescription.contains(key))
    }
}

@MainActor final class GeminiValidationTests: XCTestCase {
    func testSuccessfulCheckLeavesCheckingState() async {
        let controller = GeminiValidationController()
        controller.keyStored()
        let task = controller.check(key: "fixture", model: "gemini-listed", http: immediateFixture("gemini-listed"))
        XCTAssertEqual(controller.snapshot.phase, .checking)
        await task?.value
        XCTAssertEqual(controller.snapshot.phase, .checked)
        XCTAssertEqual(controller.snapshot.models, ["gemini-listed"])
        XCTAssertTrue(controller.snapshot.message.contains("Send a message"))
    }
    func testHTTPFailuresReplaceThePendingMessageAndCanBeRetried() async throws {
        for code in [400, 401, 403, 429, 503] {
            let http = FixtureHTTP { request in
                let body: JSONValue = ["error": ["message": "Fixture provider error", "status": "PERMISSION_DENIED"]]
                return (try body.data(), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            }
            let controller = GeminiValidationController()
            await controller.check(key: "fixture", model: "gemini-listed", http: http)?.value
            XCTAssertEqual(controller.snapshot.phase, .failed)
            XCTAssertTrue(controller.snapshot.message.contains("HTTP \(code)"))
            XCTAssertFalse(controller.snapshot.isChecking)
            await controller.check(key: "replacement-fixture", model: "gemini-listed", http: immediateFixture("gemini-listed"))?.value
            XCTAssertEqual(controller.snapshot.phase, .checked)
        }
    }
    func testMissingModelKeepsTheReturnedChoices() async {
        let controller = GeminiValidationController()
        await controller.check(key: "fixture", model: "gemini-not-listed", http: immediateFixture("gemini-listed"))?.value
        XCTAssertEqual(controller.snapshot.phase, .chooseModel)
        XCTAssertEqual(controller.snapshot.models, ["gemini-listed"])
        controller.selectModel("gemini-listed")
        XCTAssertEqual(controller.snapshot.phase, .checked)
    }
    func testOfflineFailureIsVisibleAndDoesNotClearTheStoredKeyState() async {
        let controller = GeminiValidationController()
        let http = FixtureHTTP { _ in throw URLError(.notConnectedToInternet) }
        await controller.check(key: "fixture", model: "m", http: http)?.value
        XCTAssertEqual(controller.snapshot.phase, .failed)
        XCTAssertTrue(controller.snapshot.message.contains("No internet"))
        XCTAssertTrue(controller.snapshot.message.contains("still saved"))
    }
    func testDeadlineStopsSpinnerEvenWhenTransportIgnoresCancellation() async throws {
        let began = expectation(description: "Fixture network started")
        let expired = expectation(description: "Deadline updated visible state")
        let http = SuspendedGeminiHTTPFixture { began.fulfill() }
        let controller = GeminiValidationController()
        controller.onChange = { state in if state.phase == .failed { expired.fulfill() } }
        let task = controller.check(key: "fixture", model: "gemini-listed", http: http, timeoutNanoseconds: 30_000_000)
        await fulfillment(of: [began, expired], timeout: 2)
        XCTAssertEqual(controller.snapshot.phase, .failed)
        XCTAssertFalse(controller.snapshot.isChecking)
        let expiredState = controller.snapshot
        try await http.resolve(catalogFixture("gemini-listed")); await task?.value
        XCTAssertEqual(controller.snapshot, expiredState, "Late success replaced a timeout")
    }
    func testReplacementKeyCannotBeOverwrittenByOldResponse() async throws {
        let began = expectation(description: "Old request started")
        let http = SuspendedGeminiHTTPFixture { began.fulfill() }
        let controller = GeminiValidationController()
        let old = controller.check(key: "old-fixture", model: "gemini-old", http: http)
        await fulfillment(of: [began], timeout: 2)
        controller.keyStored()
        await controller.check(key: "new-fixture", model: "gemini-new", http: immediateFixture("gemini-new"))?.value
        let newState = controller.snapshot
        try await http.resolve(catalogFixture("gemini-old")); await old?.value
        XCTAssertEqual(controller.snapshot, newState)
    }
    func testRemovingKeyInvalidatesInFlightCheck() async throws {
        let began = expectation(description: "Request started")
        let http = SuspendedGeminiHTTPFixture { began.fulfill() }
        let controller = GeminiValidationController()
        let task = controller.check(key: "fixture", model: "gemini-old", http: http)
        await fulfillment(of: [began], timeout: 2)
        controller.clear()
        try await http.resolve(catalogFixture("gemini-old")); await task?.value
        XCTAssertEqual(controller.snapshot.phase, .noKey)
        XCTAssertTrue(controller.snapshot.models.isEmpty)
    }
    func testModelChangeDuringCheckUsesTheLatestSelection() async throws {
        let began = expectation(description: "Request started")
        let http = SuspendedGeminiHTTPFixture { began.fulfill() }
        let controller = GeminiValidationController()
        let task = controller.check(key: "fixture", model: "gemini-old", http: http)
        await fulfillment(of: [began], timeout: 2)
        controller.selectModel("gemini-new")
        try await http.resolve(catalogFixture("gemini-new")); await task?.value
        XCTAssertEqual(controller.snapshot.phase, .checked)
        XCTAssertTrue(controller.snapshot.message.contains("gemini-new"))
    }
    func testEmptyKeyNeverDispatchesARequest() async {
        let controller = GeminiValidationController(); let http = immediateFixture("gemini-listed")
        let task = controller.check(key: " \n", model: "gemini-listed", http: http)
        XCTAssertNil(task); XCTAssertEqual(controller.snapshot.phase, .noKey)
        let requests = await http.requests; XCTAssertTrue(requests.isEmpty)
    }
}
