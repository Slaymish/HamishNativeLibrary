import Foundation
import NativeCore

/// Reuse strict validation with an app's existing envelope and merge transaction, without data migration.
public enum StrictJSONDocument {
    public enum Fences: Sendable { case jsonOnly, jsonOrUnlabelled }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data, schema: PayloadSchema,
        maximumBytes: Int = 2_000_000, fences: Fences = .jsonOnly) throws -> Value {
        guard maximumBytes > 0, data.count <= maximumBytes,
              var text = String(data: data, encoding: .utf8) else {
            throw InterchangeError.invalid("Import must be UTF-8 JSON within the configured size limit.")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), let newline = text.firstIndex(of: "\n") {
            let header = String(text[..<newline])
            guard header == "```json" || (fences == .jsonOrUnlabelled && header == "```") else {
                throw InterchangeError.invalid("Expected a JSON code block.")
            }
            text = String(text[text.index(after: newline)..<text.index(text.endIndex, offsetBy: -3)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized = Data(text.utf8)
        try schema.validate(NativeJSON.decode(JSONValue.self, from: normalized))
        return try NativeJSON.decode(type, from: normalized)
    }
}
