import Foundation

/// Retains only sanitized fields, never the API key or raw response body.
public struct GeminiAPIError: LocalizedError, Equatable, Sendable {
    public let statusCode: Int
    public let reason: String?
    public let detail: String
    public init(data: Data, statusCode: Int, key: String) {
        self.statusCode = statusCode
        let error = (try? JSONValue.parse(Data(data.prefix(32768))))?["error"] ?? .null
        let code = error["details"].array.compactMap { $0["reason"].string }.first ?? error["status"].string
        self.reason = code.flatMap { value in
            value != key && value.count <= 100 && value.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 95 } ? value : nil
        }
        self.detail = Self.redacted(error["message"].string ?? "", key: key)
    }
    public var errorDescription: String? {
        let advice: String
        switch statusCode {
        case 400: advice = "Google rejected the request. Check the key and its Google AI Studio project."
        case 401: advice = "Google did not accept this API key. Replace it with a valid Gemini key."
        case 402: advice = "Google requires available billing credits for this request. Check the project's billing status."
        case 403: advice = "Google denied API access. Check the key's API restrictions and project permissions."
        case 404: advice = "Google could not find the model or endpoint. Check the selected model."
        case 429: advice = "Google reported a rate or quota limit. Check the project's limits before retrying."
        case 500...599: advice = "Google is temporarily unavailable. Try checking again later."
        default: advice = "Google could not complete this request."
        }
        return "\(advice) (HTTP \(statusCode)\(reason.map { ", " + $0 } ?? ""))" + (detail.isEmpty ? "" : "\n" + detail)
    }
    public static func redacted(_ text: String, key: String = "") -> String {
        let value = key.isEmpty ? text : text.replacingOccurrences(of: key, with: "[key redacted]")
        return String(ContentRedactor.clean(value).prefix(1000))
    }
    public static func userMessage(_ error: Error, key: String = "") -> String {
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "Google's connection check timed out. The key is still saved. Check your network and retry."
            case .notConnectedToInternet: return "No internet connection. The key is still saved. Reconnect and retry."
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach Google. The key is still saved. Check your network or VPN and retry."
            case .cancelled: return "Connection check cancelled. The key is still saved."
            default: return "Could not connect securely to Google (network error \(error.code.rawValue)). Check the connection and retry."
            }
        }
        return redacted(error.localizedDescription, key: key)
    }
}

public struct GeminiValidationSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case noKey, stored, checking, checked, chooseModel, failed }
    public let phase: Phase
    public let models: [String]
    public let message: String
    public var isChecking: Bool { phase == .checking }
    public init(phase: Phase = .noKey, models: [String] = [], message: String = "No Gemini key stored.") {
        self.phase = phase; self.models = models; self.message = message
    }
}

/// Shared by the native screen and portable regression tests.
/// The independent deadline updates the UI even if a transport ignores cancellation.
@MainActor public final class GeminiValidationController {
    public private(set) var snapshot = GeminiValidationSnapshot() { didSet { onChange?(snapshot) } }
    public var onChange: ((GeminiValidationSnapshot) -> Void)?
    private var revision = UUID()
    private var selectedModel = ""
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    public init() {}
    deinit { operation?.cancel(); deadline?.cancel() }
    private func invalidate() {
        revision = UUID(); operation?.cancel(); operation = nil; deadline?.cancel(); deadline = nil
    }
    public func keyStored() {
        invalidate(); snapshot = .init(phase: .stored, message: "Key saved on this phone. Check the connection to Google.")
    }
    public func clear() { invalidate(); snapshot = .init() }
    public func fail(_ error: Error) {
        invalidate(); snapshot = .init(phase: .failed, message: GeminiAPIError.userMessage(error))
    }
    public func cancel() {
        guard snapshot.isChecking else { return }
        invalidate(); snapshot = .init(phase: .stored, message: "Check cancelled. The key is still saved; you can retry.")
    }
    public func selectModel(_ value: String) {
        selectedModel = GeminiClient.normalizedModelID(value)
        if [.checked, .chooseModel].contains(snapshot.phase) { complete(snapshot.models) }
    }
    private func complete(_ models: [String]) {
        if models.contains(selectedModel) {
            snapshot = .init(phase: .checked, models: models,
                             message: "Google accepted the key and lists \(selectedModel). Send a message to test replies and quota.")
        } else {
            snapshot = .init(phase: .chooseModel, models: models,
                             message: models.isEmpty ? "Google accepted the key but returned no Gemini generation models. Check its project access."
                             : "Google accepted the key, but the selected model wasn't listed. Choose one from Google models below.")
        }
    }
    @discardableResult public func check(key: String, model: String, http: any HTTPClient = DirectHTTP(), timeoutNanoseconds: UInt64 = 25_000_000_000) -> Task<Void, Never>? {
        invalidate()
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { snapshot = .init(); return nil }
        selectedModel = GeminiClient.normalizedModelID(model)
        let epoch = revision
        let client = GeminiClient(key: key, model: selectedModel, http: http)
        snapshot = .init(phase: .checking, message: "Checking the saved key with Google…")
        operation = Task { [weak self] in
            do {
                let models = try await client.availableModels()
                guard let self, self.revision == epoch, !Task.isCancelled else { return }
                self.deadline?.cancel(); self.deadline = nil; self.operation = nil
                self.complete(models)
            } catch {
                guard let self, self.revision == epoch, !Task.isCancelled else { return }
                self.deadline?.cancel(); self.deadline = nil; self.operation = nil
                self.snapshot = .init(phase: .failed, message: GeminiAPIError.userMessage(error, key: key))
            }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            guard let self, self.revision == epoch, self.snapshot.isChecking else { return }
            self.invalidate()
            self.snapshot = .init(phase: .failed, message: "Google didn't finish the connection check in time. The key is still saved. Check your network and retry.")
        }
        return operation
    }
}
