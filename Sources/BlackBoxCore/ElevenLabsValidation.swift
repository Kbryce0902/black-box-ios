import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keeps only bounded, redacted provider error fields; no keys or raw bodies are retained.
public struct ElevenLabsAPIError: LocalizedError, Equatable, Sendable {
    public let statusCode: Int
    public let reason: String?
    public let detail: String
    public let operation: String
    public init(data: Data, statusCode: Int, request: URLRequest) {
        self.statusCode = statusCode
        let key = request.value(forHTTPHeaderField: "xi-api-key") ?? ""
        let value = (try? JSONValue.parse(Data(data.prefix(32768)))) ?? .null
        let body = value["detail"]
        let code = body["status"].string ?? value["error"]["code"].string ?? value["status"].string
        self.reason = code.flatMap { code in
            code == Self.redacted(code, key: key) && code.count <= 100 && code.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 95].contains($0) } ? code : nil
        }
        let text = body["message"].string ?? body.string ?? value["error"]["message"].string ?? value["message"].string
            ?? body.array.prefix(3).compactMap { $0["msg"].string }.joined(separator: "; ")
        self.detail = Self.redacted(text, key: key)
        let path = request.url?.path ?? ""
        self.operation = path == "/v1/models" ? "Model check" : path.hasPrefix("/v1/text-to-speech/") ? "Speech request" : "Voice check"
    }
    public static func redacted(_ text: String, key: String = "") -> String {
        let clean = key.isEmpty ? text : text.replacingOccurrences(of: key, with: "[key redacted]")
        return String(ContentRedactor.clean(clean).prefix(1000))
    }
    public var errorDescription: String? {
        let advice: String
        switch reason?.lowercased() {
        case "invalid_api_key", "invalid_api_key_id", "authentication_error": advice = "ElevenLabs rejected this API key. Check the saved key."
        case "missing_permissions", "permission_denied", "insufficient_permissions":
            advice = "This key lacks endpoint permission. Checks use Models/Voices read access; playback uses Text to Speech. Check the permission named below."
        case "voice_not_found", "voice_does_not_exist", "voice_access_denied":
            advice = "The voice is unavailable to this key. Check the Voice ID and whether the voice is enabled in the same ElevenLabs workspace."
        case "model_not_found", "invalid_model_id", "invalid_tts_model": advice = "Choose an exact API ID from Speech models, such as eleven_v4."
        case "quota_exceeded", "insufficient_credits": advice = "ElevenLabs reported an account or key quota limit. Check its usage and credit limits."
        case "voice_not_finetuned", "voice_not_fine_tuned", "voice_not_ready": advice = "ElevenLabs says this voice is not ready for the selected model. Check its processing or verification status there."
        case "detected_unusual_activity", "captcha_required", "pro_voice_not_verified": advice = "ElevenLabs requires an account or voice verification step. Complete the required step in ElevenLabs."
        default:
            switch statusCode {
            case 401, 403: advice = "ElevenLabs denied access. Check the key's endpoint permissions, voice access and IP restrictions."
            case 400, 422: advice = "ElevenLabs rejected this request. See its details below for the key, voice or model issue."
            case 404: advice = "ElevenLabs could not find this voice or resource. Check its Voice ID and workspace."
            case 429: advice = "ElevenLabs reported a rate or quota limit. Wait and check its usage limits before retrying."
            case 500...599: advice = "ElevenLabs is temporarily unavailable. Try again later."
            default: advice = "ElevenLabs returned an unexpected response."
            }
        }
        return "\(operation): \(advice) (HTTP \(statusCode)\(reason.map { ", " + $0 } ?? ""))" + (detail.isEmpty ? "" : "\n" + detail)
    }
    public static func userMessage(_ error: Error, key: String = "") -> String {
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "ElevenLabs timed out. The key is still saved. Check the connection and retry."
            case .notConnectedToInternet: return "No internet connection. The ElevenLabs key is still saved."
            case .cancelled: return "ElevenLabs check cancelled. The key is still saved."
            default: return "Couldn't reach ElevenLabs (network error \(error.code.rawValue)). Check your network or VPN and retry."
            }
        }
        return redacted(error.localizedDescription, key: key)
    }
}

public struct ElevenValidationSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case noKey, stored, checking, checked, chooseModel, failed }
    public let phase: Phase
    public let models: [ElevenSpeechModel]
    public let message: String
    public var isChecking: Bool { phase == .checking }
    public init(phase: Phase = .noKey, models: [ElevenSpeechModel] = [], message: String = "No ElevenLabs key stored.") {
        self.phase = phase; self.models = models; self.message = message
    }
}

@MainActor public final class ElevenValidationController {
    public private(set) var snapshot = ElevenValidationSnapshot() { didSet { onChange?(snapshot) } }
    public var onChange: ((ElevenValidationSnapshot) -> Void)?
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var revision = UUID()
    private var selectedModel = ""
    private var selectedVoiceID = ""
    private var verifiedVoice: ElevenVoice?
    public init() {}
    deinit { operation?.cancel(); deadline?.cancel() }
    private func invalidate() { revision = UUID(); operation?.cancel(); operation = nil; deadline?.cancel(); deadline = nil }
    public func keyStored() {
        invalidate(); verifiedVoice = nil
        snapshot = .init(phase: .stored, message: "Key saved. Enter a Voice ID and check the voice and model.")
    }
    public func clear() { invalidate(); verifiedVoice = nil; selectedVoiceID = ""; snapshot = .init() }
    public func voiceChanged(_ value: String) {
        let value = ElevenLabsClient.normalizedVoiceID(value)
        guard value != selectedVoiceID else { return }; selectedVoiceID = value
        guard snapshot.phase != .noKey else { return }
        let models = snapshot.models; invalidate(); verifiedVoice = nil
        snapshot = .init(phase: .stored, models: models, message: "Voice ID changed. Check voice and model again.")
    }
    public func fail(_ error: Error) {
        invalidate(); snapshot = .init(phase: .failed, models: snapshot.models, message: ElevenLabsAPIError.userMessage(error))
    }
    public func cancel() {
        guard snapshot.isChecking else { return }; invalidate()
        snapshot = .init(phase: .stored, models: snapshot.models, message: "Check cancelled. The key is still saved; you can retry.")
    }
    public func selectModel(_ value: String) {
        selectedModel = ElevenLabsClient.normalizedModelID(value)
        if [.checked, .chooseModel].contains(snapshot.phase) { complete() }
    }
    private func complete() {
        guard let verifiedVoice else { return }
        let listed = snapshot.models.contains { $0.id == selectedModel }
        snapshot = .init(phase: listed ? .checked : .chooseModel, models: snapshot.models,
                         message: listed ? "Voice metadata found: \(verifiedVoice.name). Model \(selectedModel) is listed. Use Test voice to verify actual speech access and playback."
                         : "Voice metadata found, but the model isn't listed for Text to Speech. Choose from Speech models below.")
    }
    @discardableResult public func check(key: String, voiceID: String, model: String, http: any HTTPClient = DirectHTTP(), timeoutNanoseconds: UInt64 = 25_000_000_000) -> Task<Void, Never>? {
        invalidate(); verifiedVoice = nil
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { snapshot = .init(); return nil }
        guard !ElevenLabsClient.normalizedVoiceID(voiceID).isEmpty else {
            snapshot = .init(phase: .stored, message: "Key saved. Enter a Voice ID, then check the voice and model."); return nil
        }
        selectedModel = ElevenLabsClient.normalizedModelID(model)
        selectedVoiceID = ElevenLabsClient.normalizedVoiceID(voiceID)
        let client = ElevenLabsClient(key: key, voiceID: voiceID, model: selectedModel, http: http)
        let epoch = revision
        snapshot = .init(phase: .checking, message: "Loading ElevenLabs speech models…")
        operation = Task { [weak self] in
            do {
                let models = try await client.availableModels()
                guard let self, self.revision == epoch, !Task.isCancelled else { return }
                self.snapshot = .init(phase: .checking, models: models, message: "Checking the selected Voice ID…")
                let voice = try await client.voiceInfo()
                guard self.revision == epoch, !Task.isCancelled else { return }
                self.deadline?.cancel(); self.deadline = nil; self.operation = nil
                self.verifiedVoice = voice; self.complete()
            } catch {
                guard let self, self.revision == epoch, !Task.isCancelled else { return }
                self.deadline?.cancel(); self.deadline = nil; self.operation = nil
                self.snapshot = .init(phase: .failed, models: self.snapshot.models, message: ElevenLabsAPIError.userMessage(error, key: key))
            }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            guard let self, self.revision == epoch, self.snapshot.isChecking else { return }
            self.invalidate()
            self.snapshot = .init(phase: .failed, models: self.snapshot.models, message: "ElevenLabs didn't finish the check in time. The key is still saved. Retry or use Test voice to check speech access directly.")
        }
        return operation
    }
}
