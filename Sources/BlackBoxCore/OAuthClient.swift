import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OAuthDiscovery: Codable, Sendable {
    public let resource: String
    public let issuer: String
    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let registrationEndpoint: String?
    public let revocationEndpoint: String?
    public let scopes: [String]
    public let authMethods: [String]?
    public init(resource: String, issuer: String, authorizationEndpoint: String, tokenEndpoint: String,
                registrationEndpoint: String?, revocationEndpoint: String?, scopes: [String], authMethods: [String]? = nil) {
        self.resource = resource; self.issuer = issuer; self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint; self.registrationEndpoint = registrationEndpoint
        self.revocationEndpoint = revocationEndpoint; self.scopes = scopes; self.authMethods = authMethods
    }
}
public struct OAuthRegistration: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let clientID: String
    public let redirectURI: String
    public let tokenEndpointAuthMethod: String?
    public let clientSecret: String?
    public let secretExpiresAt: Date?
    public var authenticationMethod: String { tokenEndpointAuthMethod ?? "none" }
    public init(clientID: String, redirectURI: String = OAuthClient.callback, tokenEndpointAuthMethod: String = "none",
                clientSecret: String? = nil, secretExpiresAt: Date? = nil) {
        self.clientID = clientID; self.redirectURI = redirectURI; self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
        self.clientSecret = clientSecret; self.secretExpiresAt = secretExpiresAt
    }
    public var description: String { "OAuthRegistration(method: \(authenticationMethod), credentials: [redacted])" }
    public var debugDescription: String { description }
}
public struct OAuthTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiry: Date
    public init(accessToken: String, refreshToken: String?, expiry: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiry = expiry
    }
}
public struct OAuthClient: Sendable {
    public static let resource = "https://mcp.desktopcommander.app/mcp"
    public static let callback = "com.kellen.blackbox:/oauth/callback"
    private let http: any HTTPClient
    public init(http: any HTTPClient = DirectHTTP()) { self.http = http }
    public static func trusted(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443,
              ["mcp.desktopcommander.app", "auth.desktopcommander.app"].contains(url.host) else {
            throw BBError.wire("RDC returned an untrusted OAuth endpoint.")
        }
        return url
    }
    public func discover() async throws -> OAuthDiscovery {
        let (rd, _) = try await http.data(URLRequest(url: URL(string: "https://mcp.desktopcommander.app/.well-known/oauth-protected-resource")!))
        let resource = try JSONValue.parse(rd)
        guard let identifier = resource["resource"].string, [Self.resource, "https://mcp.desktopcommander.app"].contains(identifier),
              let issuer = resource["authorization_servers"].array.first?.string else { throw BBError.wire("RDC resource discovery is incomplete.") }
        let issuerURL = try Self.trusted(issuer)
        let (ad, _) = try await http.data(URLRequest(url: issuerURL.appendingPathComponent(".well-known/oauth-authorization-server")))
        let auth = try JSONValue.parse(ad)
        guard auth["issuer"].string == issuer,
              auth["code_challenge_methods_supported"].array.contains("S256"),
              auth["grant_types_supported"].array.contains("authorization_code"),
              auth["token_endpoint_auth_methods_supported"].array.contains(where: { ["none", "client_secret_post", "client_secret_basic"].contains($0.string ?? "") }),
              let a = auth["authorization_endpoint"].string, let t = auth["token_endpoint"].string else { throw BBError.setup("RDC does not advertise browser sign-in with PKCE S256.") }
        _ = try Self.trusted(a); _ = try Self.trusted(t)
        let reg = auth["registration_endpoint"].string; if let reg { _ = try Self.trusted(reg) }
        let revoke = auth["revocation_endpoint"].string; if let revoke { _ = try Self.trusted(revoke) }
        return OAuthDiscovery(resource: identifier, issuer: issuer, authorizationEndpoint: a, tokenEndpoint: t,
                              registrationEndpoint: reg, revocationEndpoint: revoke,
                              scopes: auth["scopes_supported"].array.compactMap(\.string),
                              authMethods: auth["token_endpoint_auth_methods_supported"].array.compactMap(\.string))
    }
    private func response(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await http.data(request)
        guard (200..<300).contains(response.statusCode) else { throw RDCOAuthError(data: data, statusCode: response.statusCode, request: request) }
        return try JSONValue.parse(data)
    }
    public func register(_ discovery: OAuthDiscovery) async throws -> OAuthRegistration {
        guard let endpoint = discovery.registrationEndpoint else { throw BBError.setup("No dynamic registration endpoint. Obtain a public native client ID from RDC.") }
        let body: JSONValue = ["client_name": "Black_Box iOS", "application_type": "native", "redirect_uris": [.string(Self.callback)],
                               "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"], "token_endpoint_auth_method": "none", "scope": "mcp:tools"]
        let v = try await response(jsonRequest(Self.trusted(endpoint), body: body))
        guard let id = v["client_id"].string, !id.isEmpty,
              v["redirect_uris"].array.contains(.string(Self.callback)) else {
            throw BBError.setup("RDC registration did not return this app's exact sign-in callback.")
        }
        // RFC 8252 section 8.4 permits DCR credentials issued per installation.
        // They are never bundled in the IPA; the native flow still requires PKCE.
        let method = v["token_endpoint_auth_method"].string ?? "client_secret_basic"
        guard ["none", "client_secret_post", "client_secret_basic"].contains(method),
              (discovery.authMethods ?? ["none"]).contains(method) else { throw BBError.setup("RDC returned an unsupported client authentication method.") }
        let secret = method == "none" ? nil : v["client_secret"].string
        if method != "none", secret?.isEmpty != false { throw BBError.setup("RDC did not issue its required per-install credential. Try signing in again.") }
        let expiry = v["client_secret_expires_at"].number.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        let registration = OAuthRegistration(clientID: id, tokenEndpointAuthMethod: method, clientSecret: secret, secretExpiresAt: expiry)
        try validate(registration, discovery: discovery)
        return registration
    }
    public func validate(_ registration: OAuthRegistration, discovery: OAuthDiscovery) throws {
        guard !registration.clientID.isEmpty, registration.redirectURI == Self.callback,
              ["none", "client_secret_post", "client_secret_basic"].contains(registration.authenticationMethod),
              (discovery.authMethods ?? ["none"]).contains(registration.authenticationMethod) else { throw BBError.setup("RDC registration no longer matches this app or server. Remove local RDC credentials and sign in again.") }
        if registration.authenticationMethod != "none", registration.clientSecret?.isEmpty != false { throw BBError.setup("RDC's per-install credential is missing. Remove local RDC credentials and sign in again.") }
        if let expiry = registration.secretExpiresAt, expiry <= Date() { throw BBError.setup("RDC's per-install registration expired. Remove local RDC credentials and sign in again.") }
    }
    public func authorizationURL(_ d: OAuthDiscovery, registration: OAuthRegistration, state: String, challenge: String) throws -> URL {
        try validate(registration, discovery: d)
        guard !state.isEmpty, challenge.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else { throw BBError.invalid("Missing secure sign-in state or PKCE challenge.") }
        var c = URLComponents(url: try Self.trusted(d.authorizationEndpoint), resolvingAgainstBaseURL: false)!
        c.queryItems = ["response_type": "code", "client_id": registration.clientID, "redirect_uri": registration.redirectURI,
                        "state": state, "code_challenge": challenge, "code_challenge_method": "S256", "resource": d.resource,
                        "scope": d.scopes.filter { $0 == "mcp:tools" }.joined(separator: " ")].map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { throw BBError.invalid("Invalid authorization URL.") }; return url
    }
    public static func code(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == "com.kellen.blackbox", callback.host == nil, callback.path == "/oauth/callback", callback.fragment == nil,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == expectedState,
              items.filter({ $0.name == "code" }).count == 1, let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, !items.contains(where: { $0.name == "error" }) else { throw BBError.invalid("OAuth callback or state did not match this sign-in.") }
        return code
    }
    public static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted(by: { $0.key < $1.key }).map { $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
    }
    public func token(_ d: OAuthDiscovery, registration: OAuthRegistration, code: String? = nil, verifier: String? = nil, refresh: String? = nil) async throws -> OAuthTokens {
        try validate(registration, discovery: d)
        var fields = ["client_id": registration.clientID, "resource": d.resource]
        if let refresh { fields["grant_type"] = "refresh_token"; fields["refresh_token"] = refresh }
        else { guard let code, let verifier else { throw BBError.invalid("Missing PKCE exchange parameters.") }
            fields.merge(["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": registration.redirectURI]) { _, n in n }
        }
        var r = try authenticatedForm(d.tokenEndpoint, fields: fields, registration: registration)
        r.timeoutInterval = 30
        let v = try await response(r)
        guard let token = v["access_token"].string, !token.isEmpty, v["token_type"].string?.lowercased() == "bearer" else { throw BBError.wire("Token exchange returned no bearer token.") }
        return OAuthTokens(accessToken: token, refreshToken: v["refresh_token"].string ?? refresh,
                           expiry: Date().addingTimeInterval(v["expires_in"].number ?? 300))
    }
    public func revoke(_ d: OAuthDiscovery, registration: OAuthRegistration, tokens: OAuthTokens) async throws {
        guard let endpoint = d.revocationEndpoint else { throw BBError.setup("RDC advertises no revocation endpoint. Revoke Black_Box access in RDC's dashboard, then remove local credentials.") }
        try validate(registration, discovery: d)
        let r = try authenticatedForm(endpoint, fields: ["token": tokens.refreshToken ?? tokens.accessToken, "client_id": registration.clientID,
                                  "token_type_hint": tokens.refreshToken == nil ? "access_token" : "refresh_token"], registration: registration)
        _ = try await http.data(r)
    }
    private func authenticatedForm(_ endpoint: String, fields: [String: String], registration: OAuthRegistration) throws -> URLRequest {
        var fields = fields; var r = URLRequest(url: try Self.trusted(endpoint)); r.httpMethod = "POST"
        if registration.authenticationMethod == "client_secret_post" { fields["client_secret"] = registration.clientSecret! }
        if registration.authenticationMethod == "client_secret_basic" {
            func escaped(_ text: String) -> String { String(String(decoding: Self.form(["": text]), as: UTF8.self).dropFirst()) }
            let value = escaped(registration.clientID) + ":" + escaped(registration.clientSecret!)
            r.setValue("Basic " + Data(value.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.httpBody = Self.form(fields)
        return r
    }
}
