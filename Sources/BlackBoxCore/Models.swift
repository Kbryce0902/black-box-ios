import Foundation

public enum WorkState: String, Codable, Sendable, CaseIterable {
    case queued, running, waitingForUser = "waiting_for_user", blocked, completed, failed, cancelled, unknown
}
public struct SourceLink: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url }
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}
public struct ChatMessage: Codable, Identifiable, Sendable {
    public var id: String
    public var taskID: String
    public var role: String
    public var text: String
    public var date: Date
    public var sources: [SourceLink] = []
    public var attributionHTML: [String] = []
}
public struct TaskRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var input: String
    public var state: WorkState
    public var detail: String
    public var date: Date
    public var deviceID: String?
    public var wireHistory: [JSONValue] = []
    public var tokens: Int = 0
}
public struct ActionRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var taskID: String
    public var functionID: String
    public var name: String
    public var arguments: JSONValue
    public var deviceID: String?
    public var state: WorkState
    public var date: Date
    public var remoteCallID: String?
    public var result: JSONValue?
}
public struct Memory: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var text: String
    public init(text: String) { self.text = text }
}
public struct FolderAlias: Codable, Identifiable, Sendable {
    public var id: String { deviceID + ":" + name.lowercased() }
    public var deviceID: String
    public var name: String
    public var path: String
    public init(deviceID: String, name: String, path: String) { self.deviceID = deviceID; self.name = name; self.path = path }
}
public struct PCDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let online: Bool
    public init(id: String, name: String, online: Bool) { self.id = id; self.name = name; self.online = online }
}
public struct AppSettings: Codable, Sendable {
    public var model = "gemini-3.8-flash"
    public var voiceID = ""
    public var speechModel = "eleven_flash_v2_5"
    public var selectedDeviceID: String?
    public var helperPath = ""
    public var mute = false
    public var maxSteps = 8
    public var maxSeconds = 120
    public var maxTokens = 16000
    public var maxSpeechCharacters = 3000
    public init() {}
}
public struct ModelReply: Sendable {
    public var content: JSONValue
    public var text: String
    public var sources: [SourceLink]
    public var attributionHTML: [String]
    public var grounding: JSONValue
    public var tokens: Int
    public var calls: [JSONValue] { content["parts"].array.compactMap { $0["functionCall"].object == nil ? nil : $0["functionCall"] } }
}
public struct ToolOutcome: Sendable {
    public var value: JSONValue
    public var sources: [SourceLink] = []
    public var attributionHTML: [String] = []
    public var remoteCallID: String?
    public var isPending: Bool = false
    public var tokens: Int = 0
    public var succeeded: Bool = true
    public init(value: JSONValue, sources: [SourceLink] = [], attributionHTML: [String] = [], remoteCallID: String? = nil, isPending: Bool = false, tokens: Int = 0, succeeded: Bool = true) {
        self.value = value; self.sources = sources; self.attributionHTML = attributionHTML
        self.remoteCallID = remoteCallID; self.isPending = isPending; self.tokens = tokens; self.succeeded = succeeded
    }
}
