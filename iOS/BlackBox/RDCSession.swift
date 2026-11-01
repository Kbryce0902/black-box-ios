import Foundation
import Combine
import Security
import AuthenticationServices
import CryptoKit
import UIKit
import BlackBoxCore

@MainActor final class RDCSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var status = "Not signed in"
    @Published var discovery: OAuthDiscovery?
    @Published var devices: [PCDevice] = []
    @Published var tools: [JSONValue] = []
    @Published var diagnostic = "Native authentication has not been verified."
    @Published var authenticating = false
    let mcp = MCPClient()
    private let vault = KeychainStore()
    private let oauth = OAuthClient()
    private var browserSession: ASWebAuthenticationSession?
    private var refreshing: Task<OAuthTokens, Error>?
    private var epoch = UUID()
    var signedIn: Bool { (try? vault.load(OAuthTokens.self, account: "rdc.tokens")) != nil }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
    func probe() async throws {
        discovery = try await oauth.discover()
        status = "Discovery verified; sign-in pending"
        diagnostic = "Live metadata supports PKCE S256. Public client registration, callback and token access still need proof."
    }
    func signIn(publicClientID: String) async throws {
        guard !authenticating else { throw BBError.setup("An RDC sign-in is already in progress.") }
        authenticating = true
        defer { authenticating = false; browserSession = nil }
        try await probe()
        guard let d = discovery else { return }
        let registration: OAuthRegistration
        if !publicClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            registration = OAuthRegistration(clientID: publicClientID.trimmingCharacters(in: .whitespacesAndNewlines))
        } else { registration = try await oauth.register(d) }
        // Only an independently registered public ID can reach this point. No shared secret is accepted.
        let verifier = try random(); let state = try random()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let url = try oauth.authorizationURL(d, registration: registration, state: state, challenge: challenge)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.kellen.blackbox") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: BBError.wire("Missing sign-in callback.")) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = true
            browserSession = session
            if !session.start() { continuation.resume(throwing: BBError.setup("Could not open native sign-in.")) }
        }
        browserSession = nil
        let code = try OAuthClient.code(from: callback, expectedState: state)
        let tokens = try await oauth.token(d, registration: registration, code: code, verifier: verifier)
        try vault.save(d, account: "rdc.discovery"); try vault.save(registration, account: "rdc.registration"); try vault.save(tokens, account: "rdc.tokens")
        await mcp.reset()
        epoch = UUID(); status = "Signed in independently"
        try await refreshDevices()
    }
    func accessToken() async throws -> String {
        guard let tokens = try vault.load(OAuthTokens.self, account: "rdc.tokens") else { throw BBError.setup("Sign in to RDC within Black_Box.") }
        if tokens.expiry.timeIntervalSinceNow > 60 { return tokens.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        guard let refresh = tokens.refreshToken, let d = try vault.load(OAuthDiscovery.self, account: "rdc.discovery"),
              let registration = try vault.load(OAuthRegistration.self, account: "rdc.registration") else { throw BBError.setup("RDC session expired; sign in again.") }
        let capturedEpoch = epoch
        let job = Task { try await oauth.token(d, registration: registration, refresh: refresh) }
        refreshing = job; defer { refreshing = nil }
        do {
            let updated = try await job.value
            guard capturedEpoch == epoch else { throw CancellationError() }
            try vault.save(updated, account: "rdc.tokens"); return updated.accessToken
        } catch { status = "Authentication needs attention"; throw error }
    }
    func refreshDevices() async throws {
        let token = try await accessToken()
        tools = try await mcp.tools(token: token)
        guard tools.contains(where: { $0["name"].string == "list_devices" }) else { throw BBError.wire("RDC did not advertise list_devices.") }
        let result = try await mcp.call("list_devices", arguments: [:], token: token)
        let payload = try MCPClient.payload(result)
        devices = try MCPClient.devices(payload)
        status = "Connected · \(devices.count) paired device(s)"
        diagnostic = "Independent OAuth and device enumeration succeeded at \(Date().formatted()). Refresh, revocation and cellular actions still require acceptance tests."
    }
    func revoke() async throws {
        guard let d = try vault.load(OAuthDiscovery.self, account: "rdc.discovery"), let r = try vault.load(OAuthRegistration.self, account: "rdc.registration"),
              let t = try vault.load(OAuthTokens.self, account: "rdc.tokens") else { throw BBError.setup("No local RDC grant to revoke.") }
        try await oauth.revoke(d, registration: r, tokens: t)
        try await removeLocal()
    }
    func removeLocal() async throws {
        epoch = UUID(); refreshing?.cancel(); refreshing = nil; browserSession?.cancel(); browserSession = nil
        for account in ["rdc.tokens", "rdc.registration", "rdc.discovery"] { try vault.delete(account) }
        await mcp.reset(); devices = []; tools = []; status = "Local credentials removed"
        diagnostic = "Local removal does not revoke server access. Use RDC dashboard if server revocation is unavailable."
    }
    private func random() throws -> String {
        var b = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, b.count, &b) == errSecSuccess else { throw BBError.setup("Secure random generation failed.") }
        return Data(b).base64URLEncoded
    }
}
private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
