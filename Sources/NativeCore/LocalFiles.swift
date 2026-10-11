import Foundation
import Darwin

public enum LocalFileLock {
    /// Lock the exact legacy lock path so new and old app/CLI versions cooperate.
    /// Mutations remain synchronous; never suspend or recursively acquire the same lock inside operation.
    public static func withExclusiveLock<Result>(at url: URL, _ operation: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

public enum AtomicFile {
    /// Write privately in the destination folder, sync, then replace atomically. Caller owns locking.
    public static func write(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
            attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    /// Keep unreadable bytes for recovery. The caller decides whether quarantining is appropriate.
    public static func preserveUnreadable(at url: URL, date: Date = Date()) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        let kept = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp)-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: url, to: kept)
        return kept
    }
}

public struct SnapshotChanges<Record: Identifiable & Equatable> where Record.ID: Hashable {
    public let changed: [Record]
    public let previousValues: [Record]
    public let removed: [Record]
    public let hasCheckpoint: Bool
    public init(current: [Record], previous: [Record]?) {
        hasCheckpoint = previous != nil
        let old = Dictionary((previous ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        changed = previous == nil ? [] : current.filter { old[$0.id] != $0 }
        previousValues = changed.compactMap { old[$0.id] }
        let currentIDs = Set(current.map(\.id))
        removed = (previous ?? []).filter { !currentIDs.contains($0.id) }
    }
}
