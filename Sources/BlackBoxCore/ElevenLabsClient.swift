import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SpeechClient: Sendable {
    func audio(text: String) async throws -> AsyncThrowingStream<Data, Error>
}
public struct ElevenSpeechModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct ElevenVoice: Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct ElevenLabsClient: SpeechClient {
    private let key: String
    private let voiceID: String
    private let model: String
    private let http: any HTTPClient
    public init(key: String, voiceID: String, model: String, http: any HTTPClient = DirectHTTP()) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voiceID = Self.normalizedVoiceID(voiceID)
        self.model = Self.normalizedModelID(model); self.http = http
    }
    public static func normalizedVoiceID(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func normalizedModelID(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = value.lowercased().filter { $0.isLetter || $0.isNumber }
        // Documented display names only; unknown/future API IDs remain unchanged.
        let aliases = ["elevenv4": "eleven_v4", "elevenv4turbo": "eleven_v4_turbo", "elevenv3": "eleven_v3",
                       "elevenv3conversational": "eleven_v3_conversational", "elevenflashv25": "eleven_flash_v2_5",
                       "elevenflashv2": "eleven_flash_v2", "elevenmultilingualv2": "eleven_multilingual_v2",
                       "eleventurbov25": "eleven_turbo_v2_5"]
        return aliases[compact] ?? value
    }
    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }
    }
    private func request(_ path: String) throws -> URLRequest {
        guard !key.isEmpty else { throw BBError.setup("Enter an ElevenLabs API key in Settings.") }
        var r = URLRequest(url: URL(string: "https://api.elevenlabs.io" + path)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.setValue(key, forHTTPHeaderField: "xi-api-key"); return r
    }
    private func metadata(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await http.data(request)
        guard (200..<300).contains(response.statusCode) else { throw ElevenLabsAPIError(data: data, statusCode: response.statusCode, request: request) }
        return try JSONValue.parse(data)
    }
    public func availableModels() async throws -> [ElevenSpeechModel] {
        let value = try await metadata(request("/v1/models"))
        guard value.isArray else { throw BBError.wire("ElevenLabs returned an unreadable model list. Try checking again.") }
        var ids = Set<String>()
        return value.array.compactMap { item -> ElevenSpeechModel? in
            guard item["can_do_text_to_speech"].bool == true, let id = item["model_id"].string,
                  Self.validIdentifier(id), ids.insert(id).inserted else { return nil }
            return ElevenSpeechModel(id: id, name: String((item["name"].string ?? id).prefix(150)))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func voiceInfo() async throws -> ElevenVoice {
        guard Self.validIdentifier(voiceID) else { throw BBError.invalid("Enter the ElevenLabs Voice ID, without a share URL or extra characters.") }
        let value = try await metadata(request("/v1/voices/" + voiceID))
        guard value["voice_id"].string == voiceID else { throw BBError.wire("ElevenLabs did not return metadata for the selected voice. Recheck its Voice ID and workspace access.") }
        return ElevenVoice(id: voiceID, name: String((value["name"].string ?? "Selected voice").prefix(150)))
    }
    public func validate() async throws {
        let models = try await availableModels(); _ = try await voiceInfo()
        guard models.contains(where: { $0.id == model }) else { throw BBError.setup("The speech model was not returned by ElevenLabs. Choose an ID from Speech models.") }
    }
    public func audio(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard !key.isEmpty else { throw BBError.setup("Enter an ElevenLabs API key.") }
        guard Self.validIdentifier(voiceID) else { throw BBError.invalid("Enter the ElevenLabs Voice ID, without a share URL or extra characters.") }
        guard Self.validIdentifier(model) else { throw BBError.invalid("Choose a speech model's API ID, such as eleven_v4, from Speech models.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BBError.invalid("There is no text to speak.") }
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=pcm_24000")!
        var r = try jsonRequest(url, body: ["text": .string(text), "model_id": .string(model)])
        // output_format controls decoding. Do not override content negotiation with an unsupported Accept value.
        r.setValue(key, forHTTPHeaderField: "xi-api-key")
        return try await http.stream(r)
    }
}

/// Retains an odd byte across network chunks for signed 16-bit little-endian PCM.
public struct PCM16Decoder {
    private var tail: UInt8?
    public init() {}
    public mutating func decode(_ data: Data) -> [Float] {
        var bytes = Array(data); if let tail { bytes.insert(tail, at: 0) }; tail = nil
        if bytes.count % 2 != 0 { tail = bytes.removeLast() }
        return stride(from: 0, to: bytes.count, by: 2).map { i in Float(Int16(bitPattern: UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8))) / 32768 }
    }
    public func finish() throws { if tail != nil { throw BBError.wire("Incomplete PCM sample.") } }
}
