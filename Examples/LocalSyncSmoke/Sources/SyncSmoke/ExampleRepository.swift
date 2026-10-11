import Foundation
import NativeCore
import NativeSync

/// Fictional small-store example. The app and every CLI writer must use this same lock and recovery entrypoint.
struct ExampleRepository: LocalSyncRepository {
    let directory: URL
    struct Note: Codable, Equatable, Sendable { var title: String; var note: String }
    private var journal: SyncJournal { SyncJournal(url: directory.appendingPathComponent("sync.json"), namespace: "fictional.notes.v1") }
    private var recordsURL: URL { directory.appendingPathComponent("notes.json") }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try LocalFileLock.withExclusiveLock(at: directory.appendingPathComponent(".lock")) {
            try journal.recover(apply: apply)
            return try operation()
        }
    }
    private func read() throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: recordsURL.path) else { return [:] }
        return try NativeJSON.decode([String: Data].self, from: Data(contentsOf: recordsURL))
    }
    private func validate(_ records: [String: Data]) throws {
        for (id, bytes) in records {
            guard UUID(uuidString: id) != nil else { throw SyncFailure.invalid }
            let note = try NativeJSON.decode(Note.self, from: bytes)
            let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            guard Set(object?.keys.map { $0 } ?? []) == ["title", "note"], note.title.count <= 200, note.note.count <= 10_000 else { throw SyncFailure.invalid }
        }
    }
    private func apply(_ records: [String: Data]) throws {
        try validate(records)
        let bytes = try NativeJSON.encode(records)
        if FileManager.default.fileExists(atPath: recordsURL.path) {
            let previous = try Data(contentsOf: recordsURL)
            if previous == bytes { return }
            try AtomicFile.write(previous, to: directory.appendingPathComponent("backups/" + UUID().uuidString + ".json"))
        }
        try AtomicFile.write(bytes, to: recordsURL)
    }
    func edit(id: UUID, note: Note) throws {
        try locked {
            var next = try read(); next[id.uuidString] = try NativeJSON.encode(note)
            try journal.validateEdit(next)
            try apply(next)
        }
    }
    func storedSync() throws -> SyncReplica? { try locked { try journal.storedState(apply: apply) } }
    func joinSync(groupID: UUID) throws -> SyncReplica {
        try locked { try journal.join(groupID: groupID, readCurrent: read, validate: validate, apply: apply) }
    }
    func exchangeSync(groupID: UUID, remote: SyncReplica?) throws -> SyncReplica {
        try locked { try journal.exchange(groupID: groupID, remote: remote, readCurrent: read, validate: validate, apply: apply) }
    }
    func resolveSync(record: String, versionID: UUID) throws -> SyncReplica {
        try locked { try journal.resolve(record, versionID: versionID, readCurrent: read, validate: validate, apply: apply) }
    }
}
