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
    private var generation = UUID()
    public init(http: any HTTPClient = DirectHTTP()) { self.http = http }
    public func reset() { generation = UUID(); ready = false; sessionID = nil }
    private func request(method: String, params: JSONValue, token: String, notification: Bool = false) async throws -> JSONValue {
        let epoch = generation
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
        guard epoch == generation else { throw CancellationError() }
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
        let epoch = generation
        let v = try await request(method: "initialize", params: ["protocolVersion": .string(protocolVersion), "capabilities": [:],
                                                               "clientInfo": ["name": "Black_Box iOS", "version": "0.1.5"]], token: token)
        guard let p = v["protocolVersion"].string, ["2025-03-26", "2025-06-18", "2025-11-25"].contains(p) else { throw BBError.wire("Unsupported negotiated MCP protocol version.") }
        guard epoch == generation else { throw CancellationError() }
        protocolVersion = p
        _ = try await request(method: "notifications/initialized", params: [:], token: token, notification: true)
        guard epoch == generation else { throw CancellationError() }
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
        if let text = payload["text"].string { return try textDevices(text) }
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
    /// Adapter for RDC's observed list_devices text response. Explicit UUID and
    /// availability fields are mandatory; prose never implies a selected PC.
    private static func textDevices(_ text: String) throws -> [PCDevice] {
        func invalid() -> BBError { .wire("RDC returned an unrecognized computer list. Refresh paired devices and check RDC's dashboard.") }
        guard text.utf8.count <= 64000 else { throw invalid() }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.first == "Desktop Commander devices" else { throw invalid() }
        var index = 1; var devices: [PCDevice] = []; var ids = Set<String>()
        while index < lines.count {
            if lines[index] == "Manage devices: https://mcp.desktopcommander.app/" {
                index += 1
                if index < lines.count, lines[index] == "You can view, add, or revoke devices there." { index += 1 }
                guard index == lines.count, !devices.isEmpty else { throw invalid() }
                return devices
            }
            let prefix = "\(devices.count + 1). "
            guard lines[index].hasPrefix(prefix), index + 2 < lines.count else { throw invalid() }
            let name = String(lines[index].dropFirst(prefix.count))
            guard !name.isEmpty, name.count <= 150,
                  ["Status: Online", "Status: Offline"].contains(lines[index + 1]), lines[index + 2].hasPrefix("ID: ") else { throw invalid() }
            let id = String(lines[index + 2].dropFirst(4))
            guard UUID(uuidString: id) != nil, ids.insert(id.lowercased()).inserted else { throw invalid() }
            devices.append(PCDevice(id: id, name: name, online: lines[index + 1] == "Status: Online")); index += 3
            if index < lines.count, lines[index].hasPrefix("Last seen: ") { index += 1 }
            if index < lines.count, lines[index].hasPrefix("App version: ") { index += 1 }
        }
        guard !devices.isEmpty else { throw invalid() }
        return devices
    }
}
