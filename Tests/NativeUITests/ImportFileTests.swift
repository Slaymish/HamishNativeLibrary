import Foundation
import Testing
import NativeUI

@Test func fileImportsReadAtMostTheirConfiguredLimit() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("fictional".utf8).write(to: url)
    #expect(try ImportFile.read(url, maximumBytes: 9) == Data("fictional".utf8))
    #expect(throws: (any Error).self) { try ImportFile.read(url, maximumBytes: 8) }
    #expect(throws: (any Error).self) { try ImportFile.read(url, maximumBytes: Int.max) }
}
