import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ReasoningClient: Sendable {
    func generate(history: [JSONValue], system: String, tools: [JSONValue], grounded: Bool,
                  onText: @escaping @Sendable (String) async -> Void) async throws -> ModelReply
}
public struct GeminiClient: ReasoningClient {
    private let key: String
    private let model: String
    private let http: any HTTPClient
    public init(key: String, model: String, http: any HTTPClient = DirectHTTP()) {
        self.key = key; self.model = model; self.http = http
    }
    public func validate() async throws -> [String] {
        var r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")!)
        r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (d, _) = try await http.data(r)
        let models = try JSONValue.parse(d)["models"].array
        guard models.contains(where: { $0["name"].string == "models/" + model && $0["supportedGenerationMethods"].array.contains("generateContent") }) else {
            throw BBError.setup("Configured model is unavailable for generateContent on this key. Choose a returned model.")
        }
        return models.compactMap { $0["name"].string }
    }
    public func generate(history: [JSONValue], system: String, tools: [JSONValue], grounded: Bool,
                         onText: @escaping @Sendable (String) async -> Void) async throws -> ModelReply {
        guard !key.isEmpty else { throw BBError.setup("Enter a Gemini API key in Settings.") }
        guard !model.isEmpty, model.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) }) else { throw BBError.invalid("Invalid model identifier.") }
        var body: JSONValue = ["contents": .array(history), "systemInstruction": ["parts": [["text": .string(system)]]],
                               "generationConfig": ["maxOutputTokens": 2048]]
        var o = body.object!
        // A separate grounded request avoids assuming mixed built-in/custom tool support.
        if grounded { o["tools"] = [["google_search": [:]]] }
        else if !tools.isEmpty { o["tools"] = [["functionDeclarations": .array(tools)]] }
        body = .object(o)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!
        var request = try jsonRequest(url, body: body)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let stream = try await http.stream(request)
        var parser = SSEParser(); var parts: [JSONValue] = []; var grounding: JSONValue = [:]
        var text = ""; var tokens = 0; var finish: String?
        for try await chunk in stream {
            try Task.checkCancellation()
            for event in try parser.feed(chunk) {
                if String(data: event, encoding: .utf8) == "[DONE]" { continue }
                let value = try JSONValue.parse(event)
                if value["error"].object != nil { throw BBError.wire("Gemini returned an error event.") }
                if value["promptFeedback"]["blockReason"].string != nil { throw BBError.wire("Gemini blocked this prompt.") }
                guard let c = value["candidates"].array.first else { continue }
                for part in c["content"]["parts"].array {
                    parts.append(part) // Preserve every opaque field and original part boundary.
                    if part["thought"].bool != true, let t = part["text"].string { text += t; await onText(t) }
                }
                if c["groundingMetadata"].object != nil { grounding = c["groundingMetadata"] }
                finish = c["finishReason"].string ?? finish
                tokens = max(tokens, Int(value["usageMetadata"]["totalTokenCount"].number ?? 0))
            }
        }
        try parser.finish()
        guard finish == "STOP", !parts.isEmpty else { throw BBError.wire("Gemini response incomplete or blocked; no tools were dispatched.") }
        let links = grounding["groundingChunks"].array.compactMap { chunk -> SourceLink? in
            guard let u = chunk["web"]["uri"].string, Self.safeWebURL(u) else { return nil }
            return SourceLink(title: chunk["web"]["title"].string ?? "Source", url: u)
        }
        // Insert support markers using UTF-8 offsets before showing a grounded answer.
        let displayed = Self.citedText(text, grounding: grounding)
        let html = grounding["searchEntryPoint"]["renderedContent"].string.map { [$0] } ?? []
        return ModelReply(content: ["role": "model", "parts": .array(parts)], text: displayed,
                          sources: links, attributionHTML: html, grounding: grounding, tokens: tokens)
    }
    public static func safeWebURL(_ value: String) -> Bool {
        guard let u = URLComponents(string: value), ["https", "http"].contains(u.scheme?.lowercased() ?? ""),
              let host = u.host, !host.isEmpty, u.user == nil, u.password == nil else { return false }
        return true
    }
    public static func citedText(_ text: String, grounding: JSONValue) -> String {
        var bytes = Array(text.utf8)
        let sources = grounding["groundingChunks"].array
        let supports = grounding["groundingSupports"].array.sorted { ($0["segment"]["endIndex"].number ?? 0) > ($1["segment"]["endIndex"].number ?? 0) }
        for support in supports {
            guard let n = support["segment"]["endIndex"].number else { continue }
            let i = Int(n); guard i >= 0, i <= bytes.count else { continue }
            let refs = support["groundingChunkIndices"].array.compactMap { v -> String? in
                guard let d = v.number else { return nil }; let j = Int(d)
                guard sources.indices.contains(j), let u = sources[j]["web"]["uri"].string, safeWebURL(u) else { return nil }
                return "[\(j + 1)](\(u))"
            }.joined(separator: " ")
            if !refs.isEmpty { bytes.insert(contentsOf: Array(" \(refs)".utf8), at: i) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
