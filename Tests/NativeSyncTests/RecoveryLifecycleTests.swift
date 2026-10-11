import Foundation
import Testing
import NativeCore
import NativeSync

struct RecoveryLifecycleTests {
    @Test func rePairingKeepsDeletedRecordsDeletedWhenAnOldCopyJoins() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = SyncJournal(url: folder.appendingPathComponent("sync.json"), namespace: "fictional")
        let oldGroup = UUID(), newGroup = UUID()
        var current = ["record": Data("fictional".utf8)]
        _ = try journal.join(groupID: oldGroup, readCurrent: { current }, apply: { current = $0 })
        current = [:]
        _ = try journal.exchange(groupID: oldGroup, readCurrent: { current }, apply: { current = $0 })
        var new = try journal.join(groupID: newGroup, readCurrent: { current }, apply: { current = $0 })
        var stale = SyncReplica(namespace: "fictional", groupID: newGroup)
        try stale.reconcile(["record": Data("fictional".utf8)])
        try new.merge(stale)
        #expect(new.projection.isEmpty && new.conflicts.count == 1)
        #expect(new.records["record"]?.contains { $0.payload == nil } == true)
    }
    @Test func joiningAnotherGroupCannotDiscardAnUnreviewedConflict() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let group = UUID(), journal = SyncJournal(url: folder.appendingPathComponent("sync.json"), namespace: "fictional")
        var a = SyncReplica(namespace: "fictional", groupID: group), b = SyncReplica(namespace: "fictional", groupID: group)
        try a.reconcile(["record": Data("Mac version".utf8)]); try b.reconcile(["record": Data("Phone version".utf8)]); try a.merge(b)
        try AtomicFile.write(NativeJSON.encode(a), to: journal.url)
        let before = try Data(contentsOf: journal.url)
        #expect(throws: SyncFailure.self) {
            try journal.join(groupID: UUID(), readCurrent: { a.projection }, apply: { _ in Issue.record("Must not apply") })
        }
        #expect(try Data(contentsOf: journal.url) == before)
    }
    @Test @MainActor func disconnectedRelaunchStillShowsAndResolvesStoredConflicts() async throws {
        let group = UUID()
        var a = SyncReplica(namespace: "fictional", groupID: group), b = SyncReplica(namespace: "fictional", groupID: group)
        try a.reconcile(["record": Data("Mac version".utf8)]); try b.reconcile(["record": Data("Phone version".utf8)]); try a.merge(b)
        let repository = MemoryRepository(a)
        let service = SyncService(namespace: "fictional", serviceType: "_fictional._tcp", repository: repository, credentials: EmptyCredentials())
        await service.refreshStoredState()
        #expect(!service.isEnabled && service.conflicts.count == 1)
        let conflict = try #require(service.conflicts.first), choice = try #require(conflict.versions.first)
        await service.resolve(record: conflict.id, versionID: choice.id)
        #expect(service.conflicts.isEmpty && !service.isEnabled)
        let reopened = SyncService(namespace: "fictional", serviceType: "_fictional._tcp", repository: repository, credentials: EmptyCredentials())
        await reopened.refreshStoredState()
        #expect(reopened.conflicts.isEmpty)
    }
    @Test @MainActor func disconnectDuringPairingDoesNotReenableOrRestoreItsCredential() async throws {
        let repository = DelayedRepository(), credentials = MemoryCredentials()
        defer { repository.proceed.signal() }
        let service = SyncService(namespace: "fictional", serviceType: "_fictional._tcp", repository: repository, credentials: credentials)
        let enabling = Task { await service.enableHost() }
        for _ in 0..<200 where !repository.hasStarted { try await Task.sleep(for: .milliseconds(10)) }
        #expect(repository.hasStarted)
        service.disconnect()
        repository.proceed.signal()
        await enabling.value
        #expect(!service.isEnabled && service.pairingCode == nil)
        #expect(try credentials.read() == nil)
    }
    final class MemoryCredentials: SyncCredentials, @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?
        func read() throws -> Data? { lock.withLock { value } }
        func save(_ data: Data) throws { lock.withLock { value = data } }
        func remove() throws { lock.withLock { value = nil } }
    }
    final class DelayedRepository: LocalSyncRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        let proceed = DispatchSemaphore(value: 0)
        var hasStarted: Bool { lock.withLock { started } }
        func joinSync(groupID: UUID) throws -> SyncReplica {
            lock.withLock { started = true }
            proceed.wait()
            return SyncReplica(namespace: "fictional", groupID: groupID)
        }
        func exchangeSync(groupID: UUID, remote: SyncReplica?) throws -> SyncReplica { throw SyncFailure.invalid }
        func resolveSync(record: String, versionID: UUID) throws -> SyncReplica { throw SyncFailure.invalid }
    }
    struct EmptyCredentials: SyncCredentials {
        func read() throws -> Data? { nil }
        func save(_ data: Data) throws { throw SyncFailure.invalid }
        func remove() throws {}
    }
    final class MemoryRepository: LocalSyncRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var state: SyncReplica
        init(_ state: SyncReplica) { self.state = state }
        func storedSync() throws -> SyncReplica? { lock.withLock { state } }
        func joinSync(groupID: UUID) throws -> SyncReplica { throw SyncFailure.invalid }
        func exchangeSync(groupID: UUID, remote: SyncReplica?) throws -> SyncReplica { throw SyncFailure.invalid }
        func resolveSync(record: String, versionID: UUID) throws -> SyncReplica {
            try lock.withLock { try state.resolve(record, choosing: versionID); return state }
        }
    }
}
