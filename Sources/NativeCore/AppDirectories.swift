import Foundation

public enum AppDirectories {
    /// Uses the app's sandbox on iOS/sandboxed macOS. This does not enable device sync.
    public static func applicationSupport(appID: String) throws -> URL {
        guard !appID.isEmpty, !appID.contains("/"), appID != ".", appID != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let url = root.appendingPathComponent(appID, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return url
    }
}

public enum NativeJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
