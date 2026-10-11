import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor public enum NativeClipboard {
    @discardableResult public static func copy(_ text: String) -> Bool {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        return true
        #endif
    }
}

public enum ImportFile {
    /// One bounded read, with security-scoped access relinquished on every exit path.
    public static func read(_ url: URL, maximumBytes: Int = 2_000_000) throws -> Data {
        guard maximumBytes > 0, maximumBytes < Int.max else { throw CocoaError(.fileReadTooLarge) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
