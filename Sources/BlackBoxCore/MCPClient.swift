import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One client per independently authorized account. It never uses a ChatGPT token.
public actor MCPClient {
    private let http: any HTTPClient
    private var sessionID: String?
    private var protocolVersion = "2025-03-26"
    private var ready = false
    public init(http: any HTTPClient = DirectHTTP()) { self.http = http }
    public func reset() { ready = false; sessionID = nil }
    private func request(method: String, params: JSONValue, token: String, notification: Bool = false) async throws -> JSONValue {
        let id = UUID().uuidString
        var fields: [String: JSONValue] = ["jsonrpc": "2.0", "method": .string(method), "params": params]
        if !notification { fields["id"] = .string(id) }
        var r = try jsonRequest(URL(string: OAuthClient.resource)!, body: .object(fields))
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { r.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        // Never automatically repeat this POST on 401, timeout or expired MCP session.
        let (data, response) = try await http.data(r)
        if let s = response.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = s }
        if notification, data.isEmpty { return [:] }
        let value: JSONValue
        if (response.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") {
            var parser = SSEParser(); let events = try parser.feed(data)
            let values = try events.map(JSONValue.parse)
            guard let match = values.first(where: { $0["id"].string == id }) else { throw BBError.wire("MCP stream ended before correlated response.") }
            value = match
        } else { value = try JSONValue.parse(data) }
        guard notification || value["id"].string == id else { throw BBError.wire("MCP response ID mismatch.") }
        if value["error"].object != nil { throw BBError.wire("RDC rejected the MCP request. No automatic retry was made.") }
        return value["result"]
    }
    public func initialize(token: String) async throws {
        if ready { return }
        let v = try await request(method: "initialize", params: ["protocolVersion": .string(protocolVersion), "capabilities": [:],
                                                               "clientInfo": ["name": "Black_Box iOS", "version": "0.1.3"]], token: token)
        guard let p = v["protocolVersion"].string, ["2025-03-26", "2025-06-18", "2025-11-25"].contains(p) else { throw BBError.wire("Unsupported negotiated MCP protocol version.") }
        protocolVersion = p
        _ = try await request(method: "notifications/initialized", params: [:], token: token, notification: true)
        ready = true
    }
    public func tools(token: String) async throws -> [JSONValue] {
        try await initialize(token: token)
        var result: [JSONValue] = []; var cursor: String?
        for _ in 0..<10 {
            let v = try await request(method: "tools/list", params: cursor.map { ["cursor": .string($0)] } ?? [:], token: token)
            result += v["tools"].array; cursor = v["nextCursor"].string
            if cursor == nil { return result }
        }
        throw BBError.limit
    }
    public func call(_ name: String, arguments: JSONValue, token: String) async throws -> JSONValue {
        try await initialize(token: token)
        return try await request(method: "tools/call", params: ["name": .string(name), "arguments": arguments], token: token)
    }
    public static func payload(_ result: JSONValue) throws -> JSONValue {
        if result["isError"].bool == true { throw BBError.wire("RDC tool reported an error. Inspect Activity; success was not observed.") }
        if result["structuredContent"].object != nil { return result["structuredContent"] }
        let texts = result["content"].array.compactMap { $0["type"].string == "text" ? $0["text"].string : nil }
        if texts.count == 1, let d = texts[0].data(using: .utf8), let json = try? JSONValue.parse(d) { return json }
        return ["text": .string(texts.joined(separator: "\n"))]
    }
    /// Only documented structured variants are accepted. Unknown output is visible diagnostics, never guessed devices.
    public static func devices(_ payload: JSONValue) throws -> [PCDevice] {
        let values = payload["devices"].array.isEmpty ? payload.array : payload["devices"].array
        guard !values.isEmpty || payload["devices"].object != nil || payload["devices"] == .array([]) || payload == .array([]) else {
            throw BBError.wire("Unrecognized RDC device response. Inspect the native harness and update the versioned adapter.")
        }
        return try values.map { v in
            guard let id = v["id"].string ?? v["deviceId"].string, let name = v["name"].string else { throw BBError.wire("Device ID/name missing from RDC response.") }
            let online: Bool
            if let b = v["online"].bool ?? v["isOnline"].bool { online = b }
            else if let status = v["status"].string, ["online", "offline"].contains(status) { online = status == "online" }
            else { throw BBError.wire("Device availability missing from RDC response.") }
            return PCDevice(id: id, name: name, online: online)
        }
    }
}
