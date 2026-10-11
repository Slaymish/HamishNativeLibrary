import Foundation

public enum Confidence: String, Codable, Sendable {
    case suggested, uncertain, userConfirmed
}

public struct SharedRecord<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var revision: Int
    public var payload: Payload
    public var source: String
    public var confidence: Confidence
    public init(id: String, revision: Int = 1, payload: Payload,
                source: String = "user", confidence: Confidence = .userConfirmed) {
        self.id = id; self.revision = revision; self.payload = payload
        self.source = source; self.confidence = confidence
    }
}

public struct ProposedRecord<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var id: String
    public var baseRevision: Int?
    public var payload: Payload
    public var confidence: Confidence?
    public init(id: String, baseRevision: Int? = nil, payload: Payload, confidence: Confidence? = nil) {
        self.id = id; self.baseRevision = baseRevision; self.payload = payload; self.confidence = confidence
    }
}

public struct ExchangeBatch<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var appID: String
    public var schemaID: String
    public var schemaVersion: Int
    public var exchangeID: String
    public var source: String
    public var records: [ProposedRecord<Payload>]
    public init(appID: String, schemaID: String, schemaVersion: Int = 1,
                exchangeID: String = UUID().uuidString, source: String = "chatgpt",
                records: [ProposedRecord<Payload>]) {
        self.formatVersion = 1; self.appID = appID; self.schemaID = schemaID
        self.schemaVersion = schemaVersion; self.exchangeID = exchangeID
        self.source = source; self.records = records
    }
}

public struct ExchangeState<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var records: [String: SharedRecord<Payload>] = [:]
    public var tombstones: Set<String> = []
    public var receipts: [String: String] = [:]
    public var checkpoints: [String: [String: SharedRecord<Payload>]] = [:]
    public init() {}
}

public enum ImportAction: String, Sendable { case add, update, conflict, unchanged, blocked }

public struct ImportItem<Payload: Codable & Equatable & Sendable>: Identifiable, Sendable {
    public let id: String
    public let action: ImportAction
    public let existing: SharedRecord<Payload>?
    public let proposed: ProposedRecord<Payload>
    public let explanation: String
    public var canSelect: Bool { action == .add || action == .update || action == .conflict }
}

public struct ImportPlan<Payload: Codable & Equatable & Sendable>: Sendable {
    public let items: [ImportItem<Payload>]
    public let alreadyApplied: Bool
    let batch: ExchangeBatch<Payload>
    let expected: ExchangeState<Payload>
    let digest: String
}
