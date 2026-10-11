import Foundation
import Darwin

public enum AppDirectories {
    /// Uses the app's sandbox on iOS/sandboxed macOS. This does not enable device sync.
    public static func applicationSupport(appID: String) throws -> URL {
        let url = try applicationSupportURL(appID: appID)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Resolve an existing app folder without creating/moving data. Preserve legacy app names.
    /// Real-home mode is for an explicitly unsandboxed Mac app sharing files with its CLI.
    public static func applicationSupportURL(appID: String, realHomeOnMac: Bool = false) throws -> URL {
        guard !appID.isEmpty, !appID.contains("/"), appID != ".", appID != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        #if os(macOS)
        if realHomeOnMac {
            guard let entry = getpwuid(getuid()) else { throw CocoaError(.fileReadUnknown) }
            return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir))
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(appID, isDirectory: true)
        }
        #endif
        return try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(appID, isDirectory: true)
    }
}

public enum NativeJSON {
    public enum Dates: Sendable { case iso8601, deferredToDate }

    public static func encoder(dates: Dates = .iso8601,
        formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = dates == .iso8601 ? .iso8601 : .deferredToDate
        return encoder
    }
    public static func decoder(dates: Dates = .iso8601) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dates == .iso8601 ? .iso8601 : .deferredToDate
        return decoder
    }
    public static func encode<T: Encodable>(_ value: T, dates: Dates = .iso8601,
        formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) throws -> Data {
        try encoder(dates: dates, formatting: formatting).encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, dates: Dates = .iso8601) throws -> T {
        try decoder(dates: dates).decode(type, from: data)
    }
}
