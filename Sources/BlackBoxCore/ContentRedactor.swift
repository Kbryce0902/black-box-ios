import Foundation

/// Defense in depth for untrusted excerpts. Provider credentials are never passed to this layer at all.
public enum ContentRedactor {
    public static func clean(_ text: String) -> String {
        let patterns = [
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
            #"\bAIza[0-9A-Za-z_-]{25,}\b"#,
            #"\bsk[-_][0-9A-Za-z_-]{20,}\b"#,
            #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{12,}"#,
            #"(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password)\s*[\"']?\s*[:=]\s*[\"']?[^\s\"',;}{]{8,}"#
        ]
        return patterns.reduce(text) { value, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
            return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "[credential redacted]")
        }
    }
}
