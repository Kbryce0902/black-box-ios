import XCTest
@testable import BlackBoxCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func discoveryFixture(methods: [String] = ["none", "client_secret_post", "client_secret_basic"], revoke: Bool = false) -> OAuthDiscovery {
    OAuthDiscovery(resource: "https://mcp.desktopcommander.app", issuer: "https://mcp.desktopcommander.app", authorizationEndpoint: "https://mcp.desktopcommander.app/authorize", tokenEndpoint: "https://mcp.desktopcommander.app/token", registrationEndpoint: "https://mcp.desktopcommander.app/register", revocationEndpoint: revoke ? "https://mcp.desktopcommander.app/revoke" : nil, scopes: ["mcp:tools"], authMethods: methods)
}
private func oauthResponse(_ r: URLRequest, _ value: JSONValue, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    (try value.data(), HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}
private func fields(_ r: URLRequest) -> [String: String] {
    let text = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
    return Dictionary(uniqueKeysWithValues: (URLComponents(string: "https://fixture.invalid/?" + text)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}
private func registrationFixture(method: String = "client_secret_post", secret: JSONValue = "fixture-install-secret", redirect: String = OAuthClient.callback) -> JSONValue {
    ["client_id": "fixture-install-client", "client_secret": secret, "token_endpoint_auth_method": .string(method), "redirect_uris": [.string(redirect)], "client_secret_expires_at": 0]
}

final class RDCCompatibilityTests: XCTestCase {
    func testPerInstallationRegistrationPreservesReturnedMethodAndCredential() async throws {
        let http = FixtureHTTP { r in
            let body = try JSONValue.parse(r.httpBody!)
            XCTAssertEqual(body["application_type"].string, "native"); XCTAssertEqual(body["token_endpoint_auth_method"].string, "none")
            XCTAssertEqual(body["redirect_uris"].array, [.string(OAuthClient.callback)]); XCTAssertEqual(body["scope"].string, "mcp:tools")
            return try oauthResponse(r, registrationFixture())
        }
        let r = try await OAuthClient(http: http).register(discoveryFixture())
        XCTAssertEqual(r.authenticationMethod, "client_secret_post"); XCTAssertEqual(r.clientSecret, "fixture-install-secret")
        XCTAssertNil(r.secretExpiresAt)
        XCTAssertFalse(String(describing: r).contains("fixture-install-secret")); XCTAssertFalse(String(reflecting: r).contains("fixture-install-secret"))
    }
    func testBrowserAuthorizationRetainsPKCEAndNeverIncludesInstallationSecret() throws {
        let r = OAuthRegistration(clientID: "fixture", tokenEndpointAuthMethod: "client_secret_post", clientSecret: "fixture-install-secret")
        let url = try OAuthClient().authorizationURL(discoveryFixture(), registration: r, state: "fixture-state", challenge: String(repeating: "A", count: 43))
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["code_challenge_method"], "S256"); XCTAssertEqual(query["state"], "fixture-state")
        XCTAssertEqual(query["redirect_uri"], OAuthClient.callback); XCTAssertEqual(query["scope"], "mcp:tools")
        XCTAssertEqual(query["resource"], "https://mcp.desktopcommander.app")
        XCTAssertFalse(url.absoluteString.contains("fixture-install-secret")); XCTAssertNil(query["code_verifier"])
    }
    func testPostAuthenticationAppliesToCodeAndRefreshWithRotation() async throws {
        let http = FixtureHTTP { r in
            let f = fields(r); XCTAssertEqual(f["client_secret"], "fixture-install-secret")
            XCTAssertEqual(f["resource"], "https://mcp.desktopcommander.app"); XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(r.url!.absoluteString.contains("secret"))
            if f["grant_type"] == "authorization_code" { XCTAssertEqual(f["code_verifier"], "fixture-verifier"); XCTAssertEqual(f["redirect_uri"], OAuthClient.callback) }
            else { XCTAssertEqual(f["refresh_token"], "fixture-refresh"); XCTAssertNil(f["code_verifier"]) }
            return try oauthResponse(r, ["access_token": "fixture-access", "refresh_token": "fixture-rotated", "token_type": "Bearer", "expires_in": 3600])
        }
        let client = OAuthClient(http: http), registration = OAuthRegistration(clientID: "fixture", tokenEndpointAuthMethod: "client_secret_post", clientSecret: "fixture-install-secret")
        _ = try await client.token(discoveryFixture(), registration: registration, code: "fixture-code", verifier: "fixture-verifier")
        let refreshed = try await client.token(discoveryFixture(), registration: registration, refresh: "fixture-refresh")
        XCTAssertEqual(refreshed.refreshToken, "fixture-rotated")
        let requests = await http.requests; XCTAssertEqual(requests.count, 2)
    }
    func testPublicClientStillExchangesWithoutAnySecret() async throws {
        let http = FixtureHTTP { r in
            XCTAssertNil(fields(r)["client_secret"]); XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
            return try oauthResponse(r, ["access_token": "fixture-access", "token_type": "Bearer"])
        }
        _ = try await OAuthClient(http: http).token(discoveryFixture(), registration: OAuthRegistration(clientID: "fixture"), code: "fixture-code", verifier: "fixture-verifier")
    }
    func testBasicAuthenticationEscapesCredentialsAndAvoidsFormSecret() async throws {
        let http = FixtureHTTP { r in
            let header = try XCTUnwrap(r.value(forHTTPHeaderField: "Authorization"))
            let decoded = String(decoding: try XCTUnwrap(Data(base64Encoded: String(header.dropFirst(6)))), as: UTF8.self)
            XCTAssertEqual(decoded, "fixture%3Aid:fixture%2Bsecret%26value")
            XCTAssertNil(fields(r)["client_secret"])
            return try oauthResponse(r, ["access_token": "fixture-access", "token_type": "Bearer"])
        }
        _ = try await OAuthClient(http: http).token(discoveryFixture(), registration: OAuthRegistration(clientID: "fixture:id", tokenEndpointAuthMethod: "client_secret_basic", clientSecret: "fixture+secret&value"), refresh: "fixture-refresh")
    }
    func testMissingCredentialChangedCallbackOrUnadvertisedMethodFailClosed() async throws {
        for value in [registrationFixture(secret: .null), registrationFixture(redirect: "other.app:/callback"), registrationFixture(method: "private_key_jwt"), registrationFixture(method: "client_secret_basic")] {
            let http = FixtureHTTP { try oauthResponse($0, value) }
            do { _ = try await OAuthClient(http: http).register(discoveryFixture(methods: ["none", "client_secret_post"])); XCTFail("Unusable registration accepted") } catch {}
            let requests = await http.requests; XCTAssertEqual(requests.count, 1)
        }
    }
    func testExpiredRegistrationCannotDispatchTokenRequest() async throws {
        let http = FixtureHTTP { try oauthResponse($0, [:]) }
        let r = OAuthRegistration(clientID: "fixture", tokenEndpointAuthMethod: "client_secret_post", clientSecret: "fixture", secretExpiresAt: Date(timeIntervalSince1970: 1))
        do { _ = try await OAuthClient(http: http).token(discoveryFixture(), registration: r, refresh: "fixture"); XCTFail("Expired registration used") } catch { XCTAssertTrue(error.localizedDescription.contains("expired")) }
        let requests = await http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testLegacyPublicRegistrationAndDiscoveryDecode() throws {
        let registration = try JSONDecoder().decode(OAuthRegistration.self, from: Data(#"{"clientID":"fixture","redirectURI":"com.kellen.blackbox:/oauth/callback"}"#.utf8))
        XCTAssertEqual(registration.authenticationMethod, "none"); XCTAssertNil(registration.clientSecret)
        let data = try JSONEncoder().encode(discoveryFixture())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); object.removeValue(forKey: "authMethods")
        let legacy = try JSONDecoder().decode(OAuthDiscovery.self, from: JSONSerialization.data(withJSONObject: object))
        try OAuthClient().validate(registration, discovery: legacy)
    }
    func testRegistrationCredentialRoundTripsForProtectedStorage() throws {
        let original = OAuthRegistration(clientID: "fixture", tokenEndpointAuthMethod: "client_secret_post", clientSecret: "fixture-install-secret")
        let decoded = try JSONDecoder().decode(OAuthRegistration.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.clientSecret, "fixture-install-secret"); XCTAssertEqual(decoded.authenticationMethod, "client_secret_post")
    }
    func testTokenErrorsKeepReasonAndRedactAllRequestCredentials() throws {
        var request = URLRequest(url: URL(string: "https://mcp.desktopcommander.app/token")!)
        request.httpBody = OAuthClient.form(["client_secret": "fixture-secret", "code": "fixture-code", "code_verifier": "fixture-verifier", "refresh_token": "fixture-refresh"])
        let data = try JSONValue.object(["error": "invalid_client", "error_description": "Reject fixture-secret fixture-code fixture-verifier fixture-refresh"]).data()
        let error = RDCOAuthError(data: data, statusCode: 401, request: request)
        XCTAssertTrue(error.localizedDescription.contains("invalid_client")); XCTAssertTrue(error.localizedDescription.contains("RDC token exchange"))
        for secret in ["fixture-secret", "fixture-code", "fixture-verifier", "fixture-refresh"] { XCTAssertFalse(error.localizedDescription.contains(secret)) }
    }
    func testProviderTokenFailureIsNotAutomaticallyRetried() async throws {
        let http = FixtureHTTP { try oauthResponse($0, ["error": "server_error", "error_description": "Fixture provider failure"], status: 500) }
        do { _ = try await OAuthClient(http: http).token(discoveryFixture(), registration: OAuthRegistration(clientID: "fixture"), refresh: "fixture-refresh"); XCTFail("Provider error ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("HTTP 500")); XCTAssertTrue(error.localizedDescription.contains("server_error")) }
        let requests = await http.requests; XCTAssertEqual(requests.count, 1)
    }
    func testRevokeUsesRegisteredClientAuthentication() async throws {
        let http = FixtureHTTP { r in
            XCTAssertEqual(fields(r)["client_secret"], "fixture-secret"); XCTAssertEqual(fields(r)["token_type_hint"], "refresh_token")
            return try oauthResponse(r, [:])
        }
        try await OAuthClient(http: http).revoke(discoveryFixture(revoke: true), registration: OAuthRegistration(clientID: "fixture", tokenEndpointAuthMethod: "client_secret_post", clientSecret: "fixture-secret"), tokens: OAuthTokens(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiry: Date()))
    }
    func testDiscoveryRequiresPKCEAndAllowsAdvertisedPostAuthentication() async throws {
        for pkce in [true, false] {
            let http = FixtureHTTP { r in
                if r.url!.path.contains("oauth-protected-resource") { return try oauthResponse(r, ["resource": "https://mcp.desktopcommander.app", "authorization_servers": ["https://mcp.desktopcommander.app"]]) }
                return try oauthResponse(r, ["issuer": "https://mcp.desktopcommander.app", "authorization_endpoint": "https://mcp.desktopcommander.app/authorize", "token_endpoint": "https://mcp.desktopcommander.app/token", "registration_endpoint": "https://mcp.desktopcommander.app/register", "scopes_supported": ["mcp:tools"], "grant_types_supported": ["authorization_code"], "code_challenge_methods_supported": pkce ? ["S256"] : ["plain"], "token_endpoint_auth_methods_supported": ["client_secret_post"]])
            }
            do { let d = try await OAuthClient(http: http).discover(); XCTAssertTrue(pkce); XCTAssertEqual(d.authMethods, ["client_secret_post"]) }
            catch { XCTAssertFalse(pkce, error.localizedDescription) }
        }
    }
    func testInvalidCallbackFragmentAndDuplicateCodesAreRejected() {
        for text in ["com.kellen.blackbox:/oauth/callback?state=s&code=a#ignored", "com.kellen.blackbox:/oauth/callback?state=s&code=a&code=b", "com.kellen.blackbox:/oauth/callback?state=s&error=access_denied"] {
            XCTAssertThrowsError(try OAuthClient.code(from: URL(string: text)!, expectedState: "s"))
        }
    }
    func testObservedDeviceListTextParsesExplicitAvailabilityAndIDs() throws {
        let text = "Desktop Commander devices\n\n1. Fixture-PC\n   Status: Online\n   ID: 11111111-1111-4111-8111-111111111111\n   Last seen: now\n   App version: fixture\n\n2. Online-in-name\n   Status: Offline\n   ID: 22222222-2222-4222-8222-222222222222\n\nManage devices: https://mcp.desktopcommander.app/\nYou can view, add, or revoke devices there."
        let devices = try MCPClient.devices(["text": .string(text)])
        XCTAssertEqual(devices.count, 2); XCTAssertTrue(devices[0].online); XCTAssertFalse(devices[1].online)
        XCTAssertEqual(devices[0].id, "11111111-1111-4111-8111-111111111111")
    }
    func testAmbiguousOrDuplicateDeviceRecordsAreRejected() throws {
        let header = "Desktop Commander devices\n1. Fixture-PC\n"
        for text in [header + "Status: Maybe\nID: 11111111-1111-4111-8111-111111111111", header + "ID: 11111111-1111-4111-8111-111111111111", header + "Status: Online\nID: not-an-id", header + "Status: Online\nID: 11111111-1111-4111-8111-111111111111\n2. Other\nStatus: Offline\nID: 11111111-1111-4111-8111-111111111111"] {
            XCTAssertThrowsError(try MCPClient.devices(["text": .string(text)]))
        }
    }
}

private actor SuspendedMCPHTTP: HTTPClient {
    let began: @Sendable () -> Void
    var requests: [URLRequest] = []
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var firstRequest: URLRequest?
    init(began: @escaping @Sendable () -> Void) { self.began = began }
    func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if requests.count == 1 {
            firstRequest = request
            return try await withCheckedThrowingContinuation { continuation = $0; began() }
        }
        return try reply(request, session: "fixture-new-session")
    }
    private func reply(_ request: URLRequest, session: String) throws -> (Data, HTTPURLResponse) {
        let requestBody = try JSONValue.parse(request.httpBody!)
        let data: Data
        if requestBody["method"].string == "notifications/initialized" { data = Data() }
        else { data = try JSONValue.object(["jsonrpc": "2.0", "id": requestBody["id"], "result": ["protocolVersion": "2025-03-26"]]).data() }
        return (data, HTTPURLResponse(url: request.url!, statusCode: data.isEmpty ? 202 : 200, httpVersion: nil, headerFields: ["Mcp-Session-Id": session])!)
    }
    func finish() throws {
        let continuation = self.continuation; self.continuation = nil
        continuation?.resume(returning: try reply(firstRequest!, session: "fixture-old-session"))
    }
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> { throw BBError.setup("Fixture only supports RPC data") }
}
final class RDCSessionIsolationTests: XCTestCase {
    func testResetRejectsOldInitializationAndNeverReusesItsSession() async throws {
        let began = expectation(description: "Old MCP initialize started")
        let http = SuspendedMCPHTTP { began.fulfill() }
        let client = MCPClient(http: http)
        let old = Task { try await client.initialize(token: "fixture-old-token") }
        await fulfillment(of: [began], timeout: 2)
        await client.reset(); try await http.finish()
        do { try await old.value; XCTFail("Old account initialization survived reset") } catch { XCTAssertTrue(error is CancellationError) }
        try await client.initialize(token: "fixture-new-token")
        let requests = await http.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Mcp-Session-Id"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Mcp-Session-Id"), "fixture-new-session")
        XCTAssertFalse(requests.dropFirst().contains { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-old-token" })
    }
}
