import Foundation
import Testing
import NativeCore

struct Counter: Codable, Sendable { var count = 0 }

struct StorageTests {
    func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @Test func concurrentWritersReloadAndPreserveUpdates() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("counter.json")
        let first = JSONFileStore(url: url, initial: Counter(), backupBeforeWrite: false)
        let second = JSONFileStore(url: url, initial: Counter(), backupBeforeWrite: false)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<80 {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? first : second
                    try await store.update { $0.count += 1 }
                }
            }
            try await group.waitForAll()
        }
        #expect(try await first.read().count == 80)
    }

    @Test func corruptStoreIsNeverReplaced() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("counter.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: url)
        let store = JSONFileStore(url: url, initial: Counter())
        await #expect(throws: (any Error).self) { try await store.update { $0.count += 1 } }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func failedMutationAndBackups() async throws {
        let directory = temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("counter.json")
        let store = JSONFileStore(url: url, initial: Counter())
        try await store.update { $0.count = 1 }
        enum Failure: Error { case stop }
        await #expect(throws: Failure.self) {
            try await store.update { value in value.count = 99; throw Failure.stop }
        }
        #expect(try await store.read().count == 1)
        try await store.update { $0.count = 2 }
        let backups = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try NativeJSON.decode(Counter.self, from: Data(contentsOf: backups[0])).count == 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func pathTraversalRejected() throws {
        #expect(throws: (any Error).self) { try AppDirectories.applicationSupport(appID: "../outside") }
        #expect(throws: (any Error).self) { try AppDirectories.applicationSupport(appID: "..") }
    }
}
