import Foundation
import NativeCore

/// The host holds its existing repository lock for every method. Recovery must run before normal reads/writes.
/// A pending transaction is committed to app files before the durable replica is advanced or acknowledged.
public struct SyncJournal: Sendable {
    public let url: URL
    public let namespace: String
    private var pendingURL: URL { url.appendingPathExtension("pending") }
    public init(url: URL, namespace: String) { self.url = url; self.namespace = namespace }

    public func recover(apply: ([String: Data]) throws -> Void) throws {
        guard let pending = try read(pendingURL) else { return }
        try apply(pending.projection)
        try AtomicFile.write(NativeJSON.encode(pending), to: url)
        try FileManager.default.removeItem(at: pendingURL)
    }

    /// Call under the repository lock before saving a normal app/CLI edit. Unresolved alternatives require review.
    public func validateEdit(_ current: [String: Data]) throws {
        guard var state = try read(url) else { return }
        try state.reconcile(current)
    }

    public func exchange(groupID: UUID, remote: SyncReplica? = nil,
                         readCurrent: () throws -> [String: Data],
                         validate: ([String: Data]) throws -> Void = { _ in },
                         apply: ([String: Data]) throws -> Void) throws -> SyncReplica {
        try recover(apply: apply)
        let previous = try read(url)
        var state = previous ?? SyncReplica(namespace: namespace, groupID: groupID)
        guard state.groupID == groupID else { throw SyncFailure.wrongGroup }
        try state.reconcile(readCurrent())
        if let remote { try state.merge(remote) }
        if previous != state { try commit(state, validate: validate, apply: apply) }
        return state
    }

    public func resolve(_ record: String, versionID: UUID, readCurrent: () throws -> [String: Data],
                        validate: ([String: Data]) throws -> Void = { _ in },
                        apply: ([String: Data]) throws -> Void) throws -> SyncReplica {
        try recover(apply: apply)
        guard var state = try read(url) else { throw SyncFailure.unknownConflict }
        try state.reconcile(readCurrent())
        try state.resolve(record, choosing: versionID)
        try commit(state, validate: validate, apply: apply)
        return state
    }

    /// Pairing a new group starts fresh metadata from current app data; never imports another device identity.
    public func join(groupID: UUID, readCurrent: () throws -> [String: Data],
                     validate: ([String: Data]) throws -> Void = { _ in },
                     apply: ([String: Data]) throws -> Void) throws -> SyncReplica {
        try recover(apply: apply)
        if let state = try read(url), state.groupID == groupID {
            return try exchange(groupID: groupID, readCurrent: readCurrent, validate: validate, apply: apply)
        }
        var state = SyncReplica(namespace: namespace, groupID: groupID)
        try state.reconcile(readCurrent())
        try commit(state, validate: validate, apply: apply)
        return state
    }

    private func commit(_ state: SyncReplica, validate: ([String: Data]) throws -> Void,
                        apply: ([String: Data]) throws -> Void) throws {
        try state.validate()
        try validate(state.projection)
        let bytes = try NativeJSON.encode(state)
        try AtomicFile.write(bytes, to: pendingURL)
        // On failure the pending state remains for idempotent recovery; no caller should acknowledge success.
        try apply(state.projection)
        try AtomicFile.write(bytes, to: url)
        try FileManager.default.removeItem(at: pendingURL)
    }

    private func read(_ location: URL) throws -> SyncReplica? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        do {
            let bytes = try Data(contentsOf: location)
            guard bytes.count <= SyncReplica.maximumMessageBytes else { throw SyncFailure.tooLarge }
            let state = try NativeJSON.decode(SyncReplica.self, from: bytes)
            try state.validate()
            guard state.namespace == namespace else { throw SyncFailure.wrongGroup }
            return state
        } catch let error as SyncFailure { throw error }
        catch { throw SyncFailure.corruptState }
    }
}
