import Foundation
import Testing
import NativeCore
import NativeSync

struct ReplicaTests {
    let group = UUID()
    func data(_ text: String) -> Data { Data(text.utf8) }
    func replica() -> SyncReplica { SyncReplica(namespace: "fictional", groupID: group) }

    @Test func reconnectUnionsOfflineRecordsAndConvergesIdempotently() throws {
        var a = replica(), b = replica()
        try a.reconcile(["a": data("A")]); try b.reconcile(["b": data("B")])
        try a.merge(b); try b.merge(a)
        #expect(a.projection == b.projection && a.projection.count == 2)
        let records = a.records
        try a.merge(b)
        #expect(a.records == records)
    }
    @Test func independentFieldsAndStableIDArrayEntriesMergeWithoutLosingData() throws {
        var a = replica(), b = replica()
        let original = data(#"{"name":"Old","notes":"Original","contacts":[]}"#)
        try a.reconcile(["person": original]); try b.merge(a)
        try a.reconcile(["person": data(#"{"name":"Corrected","notes":"Original","contacts":[{"id":"a","note":"Mac event"}]}"#)])
        try b.reconcile(["person": data(#"{"name":"Old","notes":"New note","contacts":[{"id":"b","note":"Phone event"}]}"#)])
        try a.merge(b); try b.merge(a)
        let value = try #require(a.projection["person"])
        let object = try JSONSerialization.jsonObject(with: value) as! [String: Any]
        #expect(object["name"] as? String == "Corrected")
        #expect(object["notes"] as? String == "New note")
        #expect((object["contacts"] as? [[String: Any]])?.count == 2)
        #expect(a.projection == b.projection && a.conflicts.isEmpty)
    }
    @Test func conflictingFieldRetainsBothVersionsUntilExplicitResolution() throws {
        var a = replica(), b = replica()
        try a.reconcile(["person": data(#"{"name":"Original"}"#)]); try b.merge(a)
        try a.reconcile(["person": data(#"{"name":"Mac correction"}"#)])
        try b.reconcile(["person": data(#"{"name":"Phone correction"}"#)])
        try a.merge(b); try b.merge(a)
        let conflict = try #require(a.conflicts.first)
        #expect(conflict.fields == ["name"] && conflict.versions.count == 2)
        let chosen = try #require(conflict.versions.first { $0.payload == data(#"{"name":"Mac correction"}"#) })
        try a.resolve("person", choosing: chosen.id); try b.merge(a)
        #expect(a.conflicts.isEmpty && b.conflicts.isEmpty && a.projection == b.projection)
    }
    @Test func unrelatedEditCannotSilentlyResolveAnExistingConflict() throws {
        var a = replica(), b = replica()
        try a.reconcile(["person": data(#"{"name":"Original","note":"Original"}"#)]); try b.merge(a)
        try a.reconcile(["person": data(#"{"name":"Mac","note":"Original"}"#)])
        try b.reconcile(["person": data(#"{"name":"Phone","note":"Original"}"#)])
        try a.merge(b)
        let original = a
        #expect(throws: SyncFailure.self) { try a.reconcile(["person": data(#"{"name":"Mac","note":"Another edit"}"#)]) }
        #expect(a == original && a.conflicts.count == 1)
    }
    @Test func deletionIsNotResurrectedByAStaleDevice() throws {
        var a = replica(), b = replica()
        try a.reconcile(["person": data("original")]); try b.merge(a)
        let stale = b
        try a.reconcile([:]); try b.merge(a); try a.merge(stale)
        #expect(a.projection.isEmpty && b.projection.isEmpty)
    }
    @Test func concurrentDeleteAndEditPreserveTheEditForReview() throws {
        var a = replica(), b = replica()
        try a.reconcile(["person": data("original")]); try b.merge(a)
        try a.reconcile([:]); try b.reconcile(["person": data("offline edit")])
        try a.merge(b); try b.merge(a)
        #expect(a.projection.isEmpty && a.conflicts.count == 1)
        let edit = try #require(a.conflicts[0].versions.first { $0.payload != nil })
        try a.resolve("person", choosing: edit.id); try b.merge(a)
        #expect(b.projection["person"] == data("offline edit"))
    }
    @Test func encodingRoundTripsAndWrongGroupsAreRejected() throws {
        var a = replica(), b = replica()
        try a.reconcile(["one": data("one")]); try b.merge(a)
        let different = SyncReplica(namespace: "other", groupID: UUID())
        #expect(throws: SyncFailure.self) { try a.merge(different) }
        let encoded = try NativeJSON.encode(a)
        let restored = try NativeJSON.decode(SyncReplica.self, from: encoded)
        #expect(restored == a)
    }
    @Test func journalRecoversAnInterruptedDomainWriteBeforeAcknowledging() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sync.json")
        let journal = SyncJournal(url: url, namespace: "fictional")
        enum Interrupted: Error { case write }
        #expect(throws: Interrupted.self) {
            try journal.exchange(groupID: group, readCurrent: { ["person": data("saved")] }, apply: { _ in throw Interrupted.write })
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        var applied: [String: Data] = [:]
        try journal.recover { applied = $0 }
        #expect(applied["person"] == data("saved"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("pending").path))
    }
    @Test func invalidDomainProjectionDoesNotLeaveAPoisonedRecoveryJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sync.json")
        let journal = SyncJournal(url: url, namespace: "fictional")
        #expect(throws: SyncFailure.self) {
            try journal.exchange(groupID: group, readCurrent: { ["bad": data("bad")] },
                validate: { _ in throw SyncFailure.invalid }, apply: { _ in Issue.record("Must not apply invalid data") })
        }
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("pending").path))
    }
    @Test func boundedFramesHandleFragmentationAndRejectOversizedMessages() throws {
        var parser = LocalMessageFramer<String>(maximumLength: 20)
        let bytes = try parser.frame("fictional")
        #expect(try parser.feed(Data(bytes.prefix(3))).isEmpty)
        #expect(try parser.feed(Data(bytes.dropFirst(3))) == ["fictional"])
        #expect(throws: SyncFailure.self) { try parser.frame(String(repeating: "x", count: 30)) }
        #expect(throws: SyncFailure.self) { try parser.feed(Data([0xff, 0xff, 0xff, 0xff])) }
    }
    @Test func pairingCodesAreBoundToTheAppNamespace() throws {
        let code = SyncInvitation(namespace: "fictional", key: Data(repeating: 7, count: 32))
        #expect(try SyncInvitation(code: code.code, namespace: "fictional") == code)
        #expect(throws: SyncFailure.self) { try SyncInvitation(code: code.code, namespace: "another app") }
    }
}
