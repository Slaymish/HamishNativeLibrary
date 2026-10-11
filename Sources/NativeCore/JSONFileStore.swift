import Foundation

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
        try AtomicFile.write(data, to: destination)
    }

    private func locked<Result>(_ action: () throws -> Result) throws -> Result {
        try LocalFileLock.withExclusiveLock(at: URL(fileURLWithPath: url.path + ".lock"), action)
    }
}
