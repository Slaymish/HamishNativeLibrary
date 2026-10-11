import Foundation
import AgentInterchange
import NativeCore

enum JSONRecordMerge {
    struct Result { var payload: Data?; var fields: [String] }

    static func materialize(_ versions: [SyncVersion]) -> Result {
        guard !versions.isEmpty else { return Result(payload: nil, fields: []) }
        let ordered = versions.sorted { left, right in
            let l = left.clock.counters[left.deviceID, default: 0], r = right.clock.counters[right.deviceID, default: 0]
            if l != r { return l < r }
            if left.deviceID != right.deviceID { return left.deviceID < right.deviceID }
            return left.id.uuidString < right.id.uuidString
        }
        if ordered.allSatisfy({ $0.payload == ordered[0].payload }) {
            return Result(payload: ordered[0].payload, fields: [])
        }
        // An intentional deletion is visible on both devices while a concurrent edit is retained for review.
        if ordered.contains(where: { $0.payload == nil }) { return Result(payload: nil, fields: ["deleted record"]) }
        let histories = ordered.map { version in
            Dictionary(version.ancestors.map { ($0.fingerprint, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let shared = Set(histories[0].keys).filter { key in histories.allSatisfy { $0[key] != nil } }
        let base = shared.compactMap { histories[0][$0] }.sorted { left, right in
            let l = left.clock.counters.values.map(Double.init).reduce(0, +)
            let r = right.clock.counters.values.map(Double.init).reduce(0, +)
            return l == r ? left.fingerprint < right.fingerprint : l > r
        }.first
        guard let base, let baseData = base.payload,
              let baseValue = try? NativeJSON.decode(JSONValue.self, from: baseData),
              var value = try? NativeJSON.decode(JSONValue.self, from: ordered[0].payload!) else {
            return Result(payload: ordered.last!.payload, fields: ["record"])
        }
        var conflicts: Set<String> = []
        for version in ordered.dropFirst() {
            guard let right = try? NativeJSON.decode(JSONValue.self, from: version.payload!) else {
                return Result(payload: ordered.last!.payload, fields: ["record"])
            }
            value = merge(base: baseValue, left: value, right: right, path: "", conflicts: &conflicts) ?? .null
        }
        return Result(payload: try? NativeJSON.encode(value, formatting: [.sortedKeys]), fields: conflicts.sorted())
    }

    private static func merge(base: JSONValue?, left: JSONValue?, right: JSONValue?, path: String,
                              conflicts: inout Set<String>, depth: Int = 0) -> JSONValue? {
        if left == right { return left }
        if left == base { return right }
        if right == base { return left }
        guard depth < 32 else { conflicts.insert(path); return right }
        if case .object(let l) = left, case .object(let r) = right {
            let b: [String: JSONValue] = { if case .object(let value) = base { return value }; return [:] }()
            var result: [String: JSONValue] = [:]
            for key in Set(b.keys).union(l.keys).union(r.keys).sorted() {
                result[key] = merge(base: b[key], left: l[key], right: r[key],
                    path: path.isEmpty ? key : path + "." + key, conflicts: &conflicts, depth: depth + 1)
            }
            return .object(result)
        }
        if case .array(let l) = left, case .array(let r) = right,
           let lm = keyed(l), let rm = keyed(r) {
            let b: [JSONValue] = { if case .array(let value) = base { return value }; return [] }()
            if let bm = keyed(b) {
                var result: [String: JSONValue] = [:]
                for id in Set(bm.keys).union(lm.keys).union(rm.keys).sorted() {
                    result[id] = merge(base: bm[id], left: lm[id], right: rm[id], path: path + "[" + id + "]",
                        conflicts: &conflicts, depth: depth + 1)
                }
                // Preserve the shared order; additions from either device follow in stable ID order.
                let baseIDs = b.compactMap(id)
                let order = baseIDs.filter { result[$0] != nil } + result.keys.filter { !baseIDs.contains($0) }.sorted()
                return .array(order.compactMap { result[$0] })
            }
        }
        conflicts.insert(path.isEmpty ? "record" : path)
        return right
    }

    private static func id(_ value: JSONValue) -> String? {
        guard case .object(let object) = value, case .string(let id) = object["id"] else { return nil }
        return id
    }
    private static func keyed(_ values: [JSONValue]) -> [String: JSONValue]? {
        var result: [String: JSONValue] = [:]
        for value in values {
            guard let id = id(value), result[id] == nil else { return nil }
            result[id] = value
        }
        return result
    }
}
