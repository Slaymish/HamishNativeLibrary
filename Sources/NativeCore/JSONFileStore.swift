import Foundation
import Darwin

/// Cooperating app/CLI processes must use this store and the same path.
/// Local filesystem only; advisory locking is not distributed/iCloud coordination.
public actor JSONFileStore<Value: Codable & Sendable> {
    public let url: URL
    private let initial: Value
    private let backupBeforeWrite: Bool

    public init(url: URL, initial: Value, backupBeforeWrite: Bool = true) {
        self.url = url
        self.initial = initial
        self.backupBeforeWrite = backupBeforeWrite
    }

    public func read() throws -> Value { try locked { try load() } }

    /// Reload, mutate, back up and save under one exclusive lock. A thrown mutation saves nothing.
    @discardableResult
    public func update<Result: Sendable>(
        _ mutate: @Sendable (inout Value) throws -> Result
    ) throws -> Result {
        try locked {
            var value = try load()
            let result = try mutate(&value)
            let data = try NativeJSON.encode(value)
            if FileManager.default.fileExists(atPath: url.path) {
                let old = try Data(contentsOf: url)
                if old == data { return result }
                if backupBeforeWrite {
                    let backups = url.deletingLastPathComponent().appendingPathComponent("backups")
                    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                    try privateWrite(old, to: backups.appendingPathComponent("\(UUID().uuidString).json"))
                }
            }
            try privateWrite(data, to: url)
            return result
        }
    }

    private func load() throws -> Value {
        do { return try NativeJSON.decode(Value.self, from: Data(contentsOf: url)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return initial
        }
        // Corruption, permission failures and incompatible versions are never treated as an empty store.
    }

    private func privateWrite(_ data: Data, to destination: URL) throws {
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

    private func locked<Result>(_ action: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try action()
    }
}
