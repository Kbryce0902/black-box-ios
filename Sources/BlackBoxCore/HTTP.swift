import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
}
public struct DirectHTTP: HTTPClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 35; config.timeoutIntervalForResource = 150
        return URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }()
    public init() {}
    public func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BBError.wire("Missing HTTP response.") }
        guard (200..<300).contains(response.statusCode) else {
            if request.url?.host == "generativelanguage.googleapis.com" {
                throw GeminiAPIError(data: data, statusCode: response.statusCode, key: request.value(forHTTPHeaderField: "x-goog-api-key") ?? "")
            }
            throw BBError.http(response.statusCode)
        }
        guard data.count <= 12_000_000 else { throw BBError.limit }
        return (data, response)
    }
    public func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        #if canImport(Darwin)
        let (bytes, response) = try await Self.session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw BBError.wire("Missing HTTP response.") }
        guard (200..<300).contains(response.statusCode) else {
            if request.url?.host == "generativelanguage.googleapis.com" {
                var errorData = Data()
                for try await byte in bytes { errorData.append(byte); if errorData.count >= 32768 { break } }
                throw GeminiAPIError(data: errorData, statusCode: response.statusCode, key: request.value(forHTTPHeaderField: "x-goog-api-key") ?? "")
            }
            throw BBError.http(response.statusCode)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var chunk = Data(); var count = 0
                    for try await byte in bytes {
                        try Task.checkCancellation(); chunk.append(byte); count += 1
                        guard count <= 12_000_000 else { throw BBError.limit }
                        if chunk.count >= 2048 || byte == 10 { continuation.yield(chunk); chunk.removeAll(keepingCapacity: true) }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #else
        // Linux verification fallback; native iOS uses URLSession.AsyncBytes above.
        let (d, _) = try await data(request)
        return AsyncThrowingStream { $0.yield(d); $0.finish() }
        #endif
    }
}
private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Provider credentials are never forwarded to a redirect target.
    }
}
public func jsonRequest(_ url: URL, method: String = "POST", body: JSONValue? = nil) throws -> URLRequest {
    var r = URLRequest(url: url, timeoutInterval: 35)
    r.httpMethod = method
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.httpBody = try body?.data()
    return r
}

/// Byte-oriented SSE framing handles split UTF-8, CRLF and multiple data lines.
public struct SSEParser {
    private var pending = Data()
    private var lines: [String] = []
    public init() {}
    public mutating func feed(_ bytes: Data) throws -> [Data] {
        pending.append(bytes)
        guard pending.count < 1_048_576 else { throw BBError.wire("SSE frame exceeds limit.") }
        var events: [Data] = []
        while let nl = pending.firstIndex(of: 10) {
            var line = String(decoding: pending[..<nl], as: UTF8.self)
            pending.removeSubrange(...nl)
            if line.last == "\r" { line.removeLast() }
            if line.isEmpty {
                if !lines.isEmpty { events.append(Data(lines.joined(separator: "\n").utf8)); lines.removeAll() }
            } else if line.hasPrefix("data:") {
                let value = String(line.dropFirst(5))
                lines.append(value.hasPrefix(" ") ? String(value.dropFirst()) : value)
                guard lines.reduce(0, { $0 + $1.utf8.count }) < 1_048_576 else { throw BBError.limit }
            }
        }
        return events
    }
    public mutating func finish() throws {
        guard pending.isEmpty, lines.isEmpty else { throw BBError.wire("Truncated event stream.") }
    }
}
