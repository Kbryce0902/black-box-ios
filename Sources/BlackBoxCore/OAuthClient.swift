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
}
public struct OAuthRegistration: Codable, Sendable {
    public let clientID: String
    public let redirectURI: String
    public init(clientID: String, redirectURI: String = OAuthClient.callback) { self.clientID = clientID; self.redirectURI = redirectURI }
}
public struct OAuthTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiry: Date
}
public struct OAuthClient: Sendable {
    public static let resource = "https://mcp.desktopcommander.app/mcp"
    public static let callback = "com.kellen.blackbox:/oauth/callback"
    private let http: any HTTPClient
    public init(http: any HTTPClient = DirectHTTP()) { self.http = http }
    public static func trusted(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
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
              auth["token_endpoint_auth_methods_supported"].array.contains("none"),
              let a = auth["authorization_endpoint"].string, let t = auth["token_endpoint"].string else { throw BBError.setup("RDC does not advertise the required public native PKCE flow.") }
        _ = try Self.trusted(a); _ = try Self.trusted(t)
        let reg = auth["registration_endpoint"].string; if let reg { _ = try Self.trusted(reg) }
        let revoke = auth["revocation_endpoint"].string; if let revoke { _ = try Self.trusted(revoke) }
        return OAuthDiscovery(resource: identifier, issuer: issuer, authorizationEndpoint: a, tokenEndpoint: t,
                              registrationEndpoint: reg, revocationEndpoint: revoke,
                              scopes: auth["scopes_supported"].array.compactMap(\.string))
    }
    public func register(_ discovery: OAuthDiscovery) async throws -> OAuthRegistration {
        guard let endpoint = discovery.registrationEndpoint else { throw BBError.setup("No dynamic registration endpoint. Obtain a public native client ID from RDC.") }
        let body: JSONValue = ["client_name": "Black_Box iOS", "application_type": "native", "redirect_uris": [.string(Self.callback)],
                               "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"], "token_endpoint_auth_method": "none", "scope": "mcp:tools"]
        let (d, _) = try await http.data(try jsonRequest(Self.trusted(endpoint), body: body))
        let v = try JSONValue.parse(d)
        guard let id = v["client_id"].string, !id.isEmpty, v["client_secret"] == .null,
              v["token_endpoint_auth_method"].string == "none", v["redirect_uris"].array.contains(.string(Self.callback)) else {
            throw BBError.setup("RDC registration did not confirm a secret-free native callback. Architecture not validated.")
        }
        return OAuthRegistration(clientID: id, redirectURI: Self.callback)
    }
    public func authorizationURL(_ d: OAuthDiscovery, registration: OAuthRegistration, state: String, challenge: String) throws -> URL {
        var c = URLComponents(url: try Self.trusted(d.authorizationEndpoint), resolvingAgainstBaseURL: false)!
        c.queryItems = ["response_type": "code", "client_id": registration.clientID, "redirect_uri": registration.redirectURI,
                        "state": state, "code_challenge": challenge, "code_challenge_method": "S256", "resource": d.resource,
                        "scope": d.scopes.filter { $0 == "mcp:tools" }.joined(separator: " ")].map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { throw BBError.invalid("Invalid authorization URL.") }; return url
    }
    public static func code(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == "com.kellen.blackbox", callback.host == nil, callback.path == "/oauth/callback",
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
        var fields = ["client_id": registration.clientID, "resource": d.resource]
        if let refresh { fields["grant_type"] = "refresh_token"; fields["refresh_token"] = refresh }
        else { guard let code, let verifier else { throw BBError.invalid("Missing PKCE exchange parameters.") }
            fields.merge(["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": registration.redirectURI]) { _, n in n }
        }
        var r = URLRequest(url: try Self.trusted(d.tokenEndpoint), timeoutInterval: 30); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.httpBody = Self.form(fields)
        let (data, _) = try await http.data(r); let v = try JSONValue.parse(data)
        guard let token = v["access_token"].string, !token.isEmpty, v["token_type"].string?.lowercased() == "bearer" else { throw BBError.wire("Token exchange returned no bearer token.") }
        return OAuthTokens(accessToken: token, refreshToken: v["refresh_token"].string ?? refresh,
                           expiry: Date().addingTimeInterval(v["expires_in"].number ?? 300))
    }
    public func revoke(_ d: OAuthDiscovery, registration: OAuthRegistration, tokens: OAuthTokens) async throws {
        guard let endpoint = d.revocationEndpoint else { throw BBError.setup("RDC advertises no revocation endpoint. Revoke Black_Box access in RDC's dashboard, then remove local credentials.") }
        var r = URLRequest(url: try Self.trusted(endpoint)); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Self.form(["token": tokens.refreshToken ?? tokens.accessToken, "client_id": registration.clientID,
                               "token_type_hint": tokens.refreshToken == nil ? "access_token" : "refresh_token"])
        _ = try await http.data(r)
    }
}
