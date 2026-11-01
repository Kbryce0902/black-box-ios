import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SpeechClient: Sendable {
    func audio(text: String) async throws -> AsyncThrowingStream<Data, Error>
}
public struct ElevenLabsClient: SpeechClient {
    private let key: String
    private let voiceID: String
    private let model: String
    private let http: any HTTPClient
    public init(key: String, voiceID: String, model: String, http: any HTTPClient = DirectHTTP()) { self.key = key; self.voiceID = voiceID; self.model = model; self.http = http }
    public func validate() async throws {
        guard !key.isEmpty, !voiceID.isEmpty else { throw BBError.setup("Enter an ElevenLabs key and accessible voice ID.") }
        var r = URLRequest(url: try voiceURL(stream: false)); r.setValue(key, forHTTPHeaderField: "xi-api-key")
        _ = try await http.data(r)
    }
    private func voiceURL(stream: Bool) throws -> URL {
        guard !voiceID.isEmpty, voiceID.allSatisfy({ $0.isLetter || $0.isNumber || "_-".contains($0) }) else { throw BBError.invalid("Invalid ElevenLabs voice ID.") }
        return URL(string: stream ? "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=pcm_24000" : "https://api.elevenlabs.io/v1/voices/\(voiceID)")!
    }
    public func audio(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard !key.isEmpty else { throw BBError.setup("Enter an ElevenLabs API key.") }
        var r = try jsonRequest(voiceURL(stream: true), body: ["text": .string(text), "model_id": .string(model)])
        r.setValue(key, forHTTPHeaderField: "xi-api-key"); r.setValue("audio/pcm", forHTTPHeaderField: "Accept")
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
