import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exposes bounded OAuth error fields, never raw bodies, forms or credentials.
public struct RDCOAuthError: LocalizedError, Sendable {
    public let statusCode: Int
    public let operation: String
    public let reason: String
    public let detail: String
    public init(data: Data, statusCode: Int, request: URLRequest) {
        self.statusCode = statusCode
        operation = request.url?.path == "/register" ? "RDC registration" : request.url?.path == "/token" ? "RDC token exchange" : "RDC request"
        let value = (try? JSONValue.parse(data)) ?? .null
        var secrets: [String] = []
        if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            let items = URLComponents(string: "https://redaction.invalid/?" + text)?.queryItems ?? []
            secrets += items.filter { ["client_secret", "code", "code_verifier", "refresh_token", "token"].contains($0.name) }.compactMap(\.value)
        }
        if let authorization = request.value(forHTTPHeaderField: "Authorization") {
            secrets.append(authorization)
            if authorization.hasPrefix("Basic "), let bytes = Data(base64Encoded: String(authorization.dropFirst(6))), let basic = String(data: bytes, encoding: .utf8), let colon = basic.firstIndex(of: ":") {
                secrets.append(String(authorization.dropFirst(6)))
                secrets.append(String(basic[basic.index(after: colon)...]).removingPercentEncoding ?? "")
            } else if authorization.hasPrefix("Bearer ") { secrets.append(String(authorization.dropFirst(7))) }
        }
        for key in ["client_secret", "access_token", "refresh_token"] { if let secret = value[key].string { secrets.append(secret) } }
        func clean(_ text: String) -> String {
            var text = text
            for secret in secrets.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
                text = text.replacingOccurrences(of: secret, with: "[credential redacted]")
                text = text.replacingOccurrences(of: secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? secret, with: "[credential redacted]")
            }
            return String(ContentRedactor.clean(text).replacingOccurrences(of: "\n", with: " ").prefix(350))
        }
        reason = clean(value["error"].string ?? "request_failed")
        detail = clean(value["error_description"].string ?? "RDC could not complete this step. Try signing in again.")
    }
    public var errorDescription: String? { "\(operation) failed (HTTP \(statusCode), \(reason)): \(detail)" }
}
