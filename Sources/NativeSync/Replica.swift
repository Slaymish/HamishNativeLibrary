import Foundation
import CryptoKit
import NativeCore

public enum SyncFailure: Error, LocalizedError, Sendable {
    case invalid, wrongGroup, tooLarge, corruptState, unknownConflict, unresolvedConflict
    public var errorDescription: String? {
        switch self {
        case .wrongGroup: "This device belongs to a different sync group. Pair the devices again."
        case .tooLarge: "The shared data exceeds the sync limit. Nothing was discarded."
        case .corruptState: "The saved sync state could not be read. It has been left untouched."
        case .unknownConflict: "This conflict changed. Refresh it before choosing a version."
        case .unresolvedConflict: "Review this record's conflicting edits in Device sync before editing it again."
        case .invalid: "The sync message was invalid. Your saved data was left untouched."
        }
    }
}

public struct SyncClock: Codable, Equatable, Sendable {
    public var counters: [String: UInt64] = [:]
    public init() {}
    public func dominates(_ other: Self) -> Bool {
        other.counters.allSatisfy { counters[$0.key, default: 0] >= $0.value }
    }
    public mutating func observe(_ other: Self) {
        for (key, value) in other.counters { counters[key] = max(counters[key, default: 0], value) }
    }
}

public struct SyncAncestor: Codable, Equatable, Sendable {
    public var clock: SyncClock
    public var payload: Data?
    var fingerprint: String {
        let bytes = (try? NativeJSON.encode(self)) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SyncVersion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var deviceID: String
    public var clock: SyncClock
    public var payload: Data?
    public var ancestors: [SyncAncestor]
    public var editedAt: Date
}

public struct SyncConflict: Sendable, Identifiable {
    public let id: String
    public let versions: [SyncVersion]
    public let fields: [String]
}

public struct SyncReplica: Codable, Equatable, Sendable {
    public static let protocolVersion = 1
    public static let maximumMessageBytes = 32 * 1024 * 1024
    public var version = Self.protocolVersion
    public let namespace: String
    public let groupID: UUID
    public let deviceID: String
    public private(set) var clock = SyncClock()
    public private(set) var records: [String: [SyncVersion]] = [:]

    public init(namespace: String, groupID: UUID, deviceID: String = UUID().uuidString) {
        self.namespace = namespace; self.groupID = groupID; self.deviceID = deviceID
    }

    public func validate() throws {
        guard version == Self.protocolVersion, !namespace.isEmpty, namespace.count <= 256,
              UUID(uuidString: deviceID) != nil, validClock(clock), records.count <= 10_000 else {
            throw SyncFailure.invalid
        }
        for (key, versions) in records {
            guard !key.isEmpty, key.count <= 512, !versions.isEmpty, versions.count <= 32,
                  Set(versions.map(\.id)).count == versions.count else { throw SyncFailure.invalid }
            for version in versions {
                guard UUID(uuidString: version.deviceID) != nil,
                      validClock(version.clock),
                      version.clock.counters[version.deviceID, default: 0] > 0,
                      clock.dominates(version.clock), version.ancestors.count <= 16,
                      (version.payload?.count ?? 0) <= 8 * 1024 * 1024 else { throw SyncFailure.invalid }
                for ancestor in version.ancestors {
                    guard validClock(ancestor.clock), version.clock.dominates(ancestor.clock),
                          (ancestor.payload?.count ?? 0) <= 8 * 1024 * 1024 else { throw SyncFailure.invalid }
                }
            }
        }
        guard try NativeJSON.encode(self).count <= Self.maximumMessageBytes else { throw SyncFailure.tooLarge }
    }
    private func validClock(_ clock: SyncClock) -> Bool {
        clock.counters.count <= 16 && clock.counters.allSatisfy { UUID(uuidString: $0.key) != nil && $0.value > 0 }
    }

    public var projection: [String: Data] {
        records.compactMapValues { JSONRecordMerge.materialize($0).payload }
    }
    public var conflicts: [SyncConflict] {
        records.keys.sorted().compactMap { key in
            let versions = records[key]!
            let result = JSONRecordMerge.materialize(versions)
            return result.fields.isEmpty ? nil : SyncConflict(id: key, versions: versions, fields: result.fields)
        }
    }

    /// Compare actual app records to the last materialized state, so offline/CLI edits become causal revisions.
    public mutating func reconcile(_ current: [String: Data]) throws {
        let previous = projection
        let conflicted = Set(conflicts.map(\.id))
        var next = self
        for key in Set(previous.keys).union(current.keys).sorted() where previous[key] != current[key] {
            if conflicted.contains(key) { throw SyncFailure.unresolvedConflict }
            try next.change(key, payload: current[key])
        }
        try next.validate()
        self = next
    }

    private mutating func change(_ key: String, payload: Data?) throws {
        guard clock.counters.count < 16 || clock.counters[deviceID] != nil,
              clock.counters[deviceID, default: 0] < UInt64.max else { throw SyncFailure.invalid }
        let previous = records[key] ?? []
        var ancestors: [SyncAncestor] = previous.flatMap { $0.ancestors + [SyncAncestor(clock: $0.clock, payload: $0.payload)] }
        // The materialized merged value is also a common parent of a subsequent edit.
        if !previous.isEmpty {
            var observed = SyncClock(); previous.forEach { observed.observe($0.clock) }
            ancestors.append(SyncAncestor(clock: observed, payload: JSONRecordMerge.materialize(previous).payload))
        }
        var unique: [String: SyncAncestor] = [:]
        ancestors.forEach { unique[$0.fingerprint] = $0 }
        ancestors = unique.values.sorted { left, right in
            let l = left.clock.counters.values.map(Double.init).reduce(0, +)
            let r = right.clock.counters.values.map(Double.init).reduce(0, +)
            return l == r ? left.fingerprint < right.fingerprint : l > r
        }
        clock.counters[deviceID, default: 0] += 1
        records[key] = [SyncVersion(id: UUID(), deviceID: deviceID, clock: clock, payload: payload,
            ancestors: Array(ancestors.prefix(16)), editedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)))]
    }

    public mutating func merge(_ remote: Self) throws {
        try remote.validate()
        guard namespace == remote.namespace, groupID == remote.groupID else { throw SyncFailure.wrongGroup }
        var merged = self
        merged.clock.observe(remote.clock)
        for (key, incoming) in remote.records {
            var byID = Dictionary((merged.records[key] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for item in incoming {
                if let previous = byID[item.id], previous != item { throw SyncFailure.invalid }
                byID[item.id] = item
            }
            let all = Array(byID.values)
            // Equal clocks with different revisions are invalid; domination must be strict.
            for left in all {
                guard !all.contains(where: { $0.id != left.id && $0.clock == left.clock }) else { throw SyncFailure.invalid }
            }
            merged.records[key] = all.filter { candidate in
                !all.contains { $0.id != candidate.id && $0.clock.dominates(candidate.clock) }
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        try merged.validate()
        self = merged
    }

    public mutating func resolve(_ key: String, choosing versionID: UUID) throws {
        guard let versions = records[key], let chosen = versions.first(where: { $0.id == versionID }) else {
            throw SyncFailure.unknownConflict
        }
        var next = self
        try next.change(key, payload: chosen.payload)
        try next.validate()
        self = next
    }
}
