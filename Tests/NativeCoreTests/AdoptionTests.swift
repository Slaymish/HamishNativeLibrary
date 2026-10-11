import Foundation
import Testing
import NativeCore

struct AdoptionTests {
    struct Dated: Codable, Equatable { var date: Date; var path: String }
    struct Item: Identifiable, Equatable { var id: Int; var text: String }

    @Test func legacyJSONEncodingRemainsByteCompatible() throws {
        let value = Dated(date: Date(timeIntervalSince1970: 1_800_000_000), path: "/fictional/path")
        let old = JSONEncoder(); old.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try NativeJSON.encode(value, dates: .deferredToDate, formatting: [.prettyPrinted, .sortedKeys])
        #expect(try data == old.encode(value))
        #expect(try NativeJSON.decode(Dated.self, from: data, dates: .deferredToDate) == value)
        old.dateEncodingStrategy = .iso8601
        #expect(try NativeJSON.encode(value, formatting: [.prettyPrinted, .sortedKeys]) == old.encode(value))
    }

    @Test func snapshotDiffKeepsIDsAndNoCheckpointIsNotAllNew() {
        let previous = [Item(id: 1, text: "old spelling"), Item(id: 2, text: "deleted")]
        let current = [Item(id: 1, text: "corrected"), Item(id: 3, text: "added")]
        let diff = SnapshotChanges(current: current, previous: previous)
        #expect(diff.changed == current)
        #expect(diff.previousValues == [previous[0]])
        #expect(diff.removed == [previous[1]])
        let initial = SnapshotChanges(current: current, previous: nil)
        #expect(!initial.hasCheckpoint && initial.changed.isEmpty && initial.removed.isEmpty)
    }

    @Test func preservingUnreadableFilesNeverOverwritesAnotherBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("city.json")
        let first = Data("first broken file".utf8), second = Data("second broken file".utf8)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try AtomicFile.write(first, to: url)
        let savedFirst = try AtomicFile.preserveUnreadable(at: url, date: date)
        try AtomicFile.write(second, to: url)
        let savedSecond = try AtomicFile.preserveUnreadable(at: url, date: date)
        #expect(savedFirst != savedSecond)
        #expect(try Data(contentsOf: savedFirst) == first)
        #expect(try Data(contentsOf: savedSecond) == second)
    }
}
