import Foundation
import NativeCore

public struct ExchangeConfiguration<Payload: Codable & Equatable & Sendable>: Sendable {
    public let appID: String
    public let schemaID: String
    public let schemaVersion: Int
    public let purpose: String
    public let payloadSchema: PayloadSchema
    public let allowedSources: Set<String>
    public let maximumBytes: Int
    public let maximumRecords: Int
    /// App-specific validation; schema validation always runs first.
    public let validatePayload: @Sendable (Payload) throws -> Void

    public init(appID: String, schemaID: String, schemaVersion: Int = 1, purpose: String,
                payloadSchema: PayloadSchema, allowedSources: Set<String> = ["chatgpt", "claude"],
                maximumBytes: Int = 2_000_000, maximumRecords: Int = 500,
                validatePayload: @escaping @Sendable (Payload) throws -> Void = { _ in }) throws {
        guard !appID.isEmpty, !schemaID.isEmpty, schemaVersion > 0,
              maximumBytes > 0, maximumBytes < Int.max, maximumRecords > 0, !allowedSources.isEmpty,
              appID.count <= 256, schemaID.count <= 256,
              allowedSources.allSatisfy({ !$0.isEmpty && $0.count <= 128 }) else {
            throw InterchangeError.invalid("Invalid exchange configuration.")
        }
        try payloadSchema.validateDefinition()
        self.appID = appID; self.schemaID = schemaID; self.schemaVersion = schemaVersion
        self.purpose = purpose; self.payloadSchema = payloadSchema; self.allowedSources = allowedSources
        self.maximumBytes = maximumBytes; self.maximumRecords = maximumRecords
        self.validatePayload = validatePayload
    }

    public var batchSchema: PayloadSchema {
        .object(properties: [
            "formatVersion": .integer(minimum: 1, maximum: 1),
            "appID": .string(maximum: 256, choices: [appID]),
            "schemaID": .string(maximum: 256, choices: [schemaID]),
            "schemaVersion": .integer(minimum: schemaVersion, maximum: schemaVersion),
            "exchangeID": .string(maximum: 128),
            "source": .string(maximum: 128, choices: allowedSources),
            "records": .array(items: .object(properties: [
                "id": .string(maximum: 128),
                "baseRevision": .nullable(.integer(minimum: 1, maximum: 2_147_483_647)),
                "confidence": .nullable(.string(maximum: 16, choices: ["suggested", "uncertain"])),
                "payload": payloadSchema
            ], required: ["id", "payload"]), maximum: maximumRecords)
        ], required: ["formatVersion", "appID", "schemaID", "schemaVersion", "exchangeID", "source", "records"])
    }

    public func decode(_ data: Data) throws -> ExchangeBatch<Payload> {
        guard data.count <= maximumBytes else { throw InterchangeError.invalid("Import exceeds the size limit.") }
        var normalized = data
        // Accept one whole fenced JSON block, never JSON extracted from surrounding prose.
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.hasPrefix("```json\n"), text.hasSuffix("\n```") {
            normalized = Data(text.dropFirst(8).dropLast(4).utf8)
        }
        let value = try NativeJSON.decode(JSONValue.self, from: normalized)
        try batchSchema.validate(value)
        let batch = try NativeJSON.decode(ExchangeBatch<Payload>.self, from: normalized)
        guard !batch.exchangeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InterchangeError.invalid("Exchange ID must not be empty.")
        }
        var ids: Set<String> = []
        for record in batch.records {
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(record.id).inserted else {
                throw InterchangeError.invalid("Record IDs must be nonempty and unique.")
            }
            try validatePayload(record.payload)
        }
        return batch
    }
}
