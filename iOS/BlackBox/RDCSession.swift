import Foundation
import Combine
import Security
import AuthenticationServices
import CryptoKit
import UIKit
import BlackBoxCore

// Each envelope is one atomic, device-only Keychain item. Never put these in
// AppSettings, SQLite, prompts, diagnostics, source or a distributed IPA.
struct RDCGrant: Codable {
    let discovery: OAuthDiscovery
    let registration: OAuthRegistration
    let tokens: OAuthTokens
}
private struct RDCPendingRegistration: Codable {
    let discovery: OAuthDiscovery
    let registration: OAuthRegistration
}

@MainActor final class RDCSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var status = "Not signed in"
    @Published var discovery: OAuthDiscovery?
    @Published var devices: [PCDevice] = []
    @Published var tools: [JSONValue] = []
    @Published var diagnostic = "Sign in to RDC to connect your paired computers."
    @Published var authenticating = false
    let mcp = MCPClient()
    private let vault = KeychainStore()
    private let oauth = OAuthClient()
    private var browserSession: ASWebAuthenticationSession?
    private var refreshing: Task<OAuthTokens, Error>?
    private var epoch = UUID()
    private var attempt: UUID?
    var signedIn: Bool { (try? loadGrant()) != nil }
    private func loadGrant() throws -> RDCGrant? {
        if let grant = try vault.load(RDCGrant.self, account: "rdc.grant") { return grant }
        // Migrate a previously successful public-client login without changing
        // its registration or losing a rotated refresh token.
        guard let d = try vault.load(OAuthDiscovery.self, account: "rdc.discovery"),
              let r = try vault.load(OAuthRegistration.self, account: "rdc.registration"),
              let t = try vault.load(OAuthTokens.self, account: "rdc.tokens") else { return nil }
        let grant = RDCGrant(discovery: d, registration: r, tokens: t)
        try vault.save(grant, account: "rdc.grant"); return grant
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
    func probe() async throws {
        let captured = epoch, d = try await oauth.discover()
        guard captured == epoch else { throw CancellationError() }
        discovery = d; status = "RDC available; sign-in pending"
        diagnostic = "RDC supports browser sign-in with PKCE. Sign in to authorize Black_Box."
    }
    private func checkAttempt(_ id: UUID) throws {
        try Task.checkCancellation()
        guard attempt == id else { throw CancellationError() }
    }
    func signIn(publicClientID: String) async throws {
        guard !authenticating else { throw BBError.setup("An RDC sign-in is already in progress.") }
        let id = UUID(); attempt = id; authenticating = true
        defer { if attempt == id { attempt = nil; authenticating = false; browserSession = nil } }
        do {
            status = "Checking RDC sign-in…"; diagnostic = status
            let d = try await oauth.discover(); try checkAttempt(id); discovery = d
            let registration: OAuthRegistration
            let manualID = publicClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !manualID.isEmpty {
                registration = OAuthRegistration(clientID: manualID)
                try oauth.validate(registration, discovery: d)
            } else {
                let pending = try vault.load(RDCPendingRegistration.self, account: "rdc.pending")
                let active = try loadGrant()
                let cached = pending.map { ($0.discovery, $0.registration) } ?? active.map { ($0.discovery, $0.registration) }
                if let (oldDiscovery, oldRegistration) = cached,
                   oldDiscovery.issuer == d.issuer, oldDiscovery.resource == d.resource,
                   (try? oauth.validate(oldRegistration, discovery: d)) != nil {
                    registration = oldRegistration
                } else {
                    status = "Registering this installation…"; diagnostic = status
                    registration = try await oauth.register(d); try checkAttempt(id)
                }
                // Cancel/retry reuses this installation's credential. It never
                // overwrites the registration belonging to an existing grant.
                try vault.save(RDCPendingRegistration(discovery: d, registration: registration), account: "rdc.pending")
            }
            try checkAttempt(id)
            let verifier = try random(), state = try random()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
            let url = try oauth.authorizationURL(d, registration: registration, state: state, challenge: challenge)
            status = "Complete RDC sign-in in the browser…"; diagnostic = status
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.kellen.blackbox") { callback, error in
                    if let error {
                        if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin { continuation.resume(throwing: CancellationError()) }
                        else { continuation.resume(throwing: error) }
                    } else if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: BBError.wire("Missing RDC sign-in callback.")) }
                }
                session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = true
                browserSession = session
                if !session.start() { continuation.resume(throwing: BBError.setup("Could not open RDC sign-in.")) }
            }
            try checkAttempt(id); browserSession = nil
            let code = try OAuthClient.code(from: callback, expectedState: state)
            status = "Completing RDC sign-in…"; diagnostic = status
            let tokens = try await oauth.token(d, registration: registration, code: code, verifier: verifier)
            try checkAttempt(id)
            try vault.save(RDCGrant(discovery: d, registration: registration, tokens: tokens), account: "rdc.grant")
            refreshing?.cancel(); refreshing = nil; epoch = UUID(); await mcp.reset(); try checkAttempt(id)
            try vault.delete("rdc.pending")
            status = "RDC signed in; loading computers…"; diagnostic = status
            try await refreshDevices(); try checkAttempt(id)
        } catch {
            if attempt == id {
                status = error is CancellationError ? "RDC sign-in canceled" : "RDC sign-in failed"
                diagnostic = error is CancellationError ? status : error.localizedDescription
            }
            throw error
        }
    }
    func cancelSignIn() {
        attempt = nil; authenticating = false
        let session = browserSession; browserSession = nil; session?.cancel()
        status = "RDC sign-in canceled"; diagnostic = status
    }
    func accessToken() async throws -> String {
        guard let grant = try loadGrant() else { throw BBError.setup("Sign in to RDC within Black_Box.") }
        if grant.tokens.expiry.timeIntervalSinceNow > 60 { return grant.tokens.accessToken }
        if let refreshing {
            let captured = epoch, updated = try await refreshing.value
            guard captured == epoch else { throw CancellationError() }
            return updated.accessToken
        }
        guard let refresh = grant.tokens.refreshToken else { throw BBError.setup("RDC session expired; sign in again.") }
        let capturedEpoch = epoch
        let job = Task { try await oauth.token(grant.discovery, registration: grant.registration, refresh: refresh) }
        refreshing = job; defer { if capturedEpoch == epoch { refreshing = nil } }
        do {
            let updated = try await job.value
            guard capturedEpoch == epoch else { throw CancellationError() }
            try vault.save(RDCGrant(discovery: grant.discovery, registration: grant.registration, tokens: updated), account: "rdc.grant")
            return updated.accessToken
        } catch {
            if capturedEpoch == epoch { status = "RDC authentication needs attention"; diagnostic = error.localizedDescription }
            throw error
        }
    }
    func refreshDevices() async throws {
        let captured = epoch, token = try await accessToken()
        let fetchedTools = try await mcp.tools(token: token)
        guard captured == epoch else { throw CancellationError() }
        guard fetchedTools.contains(where: { $0["name"].string == "list_devices" }) else { throw BBError.wire("RDC did not advertise list_devices.") }
        let result = try await mcp.call("list_devices", arguments: [:], token: token)
        let fetchedDevices = try MCPClient.devices(MCPClient.payload(result))
        guard captured == epoch else { throw CancellationError() }
        tools = fetchedTools; devices = fetchedDevices
        status = "Connected · \(devices.count) paired computer(s)"
        diagnostic = devices.isEmpty ? "RDC sign-in succeeded. Pair a computer in the RDC dashboard." : "Select your computer in the Computer tab, then check the Windows helper."
    }
    func revoke() async throws {
        guard let grant = try loadGrant() else { throw BBError.setup("No local RDC grant to revoke.") }
        try await oauth.revoke(grant.discovery, registration: grant.registration, tokens: grant.tokens)
        try await removeLocal()
    }
    func removeLocal() async throws {
        epoch = UUID(); cancelSignIn(); refreshing?.cancel(); refreshing = nil
        for account in ["rdc.grant", "rdc.pending", "rdc.tokens", "rdc.registration", "rdc.discovery"] { try vault.delete(account) }
        await mcp.reset(); devices = []; tools = []; status = "Local RDC credentials removed"
        diagnostic = "Use RDC's dashboard to revoke access on the server."
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
