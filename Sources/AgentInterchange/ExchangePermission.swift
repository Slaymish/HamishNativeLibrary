import Foundation

/// App-side consent for MANUAL exchange. This is not an OAuth token or a provider memory permission.
public struct ExchangePermission: Codable, Equatable, Sendable {
    public let appID: String
    public let source: String
    public let exportIDs: Set<String>
    public let allowsReviewedImports: Bool
    public let approvedAt: Date
    public var revokedAt: Date?

    public init(appID: String, source: String, exportIDs: Set<String>, allowsReviewedImports: Bool,
                approvedAt: Date = Date()) {
        self.appID = appID; self.source = source; self.exportIDs = exportIDs
        self.allowsReviewedImports = allowsReviewedImports; self.approvedAt = approvedAt
    }

    func require(appID: String, source: String, importing: Bool = false) throws {
        guard revokedAt == nil, self.appID == appID, self.source == source,
              !importing || allowsReviewedImports else {
            throw InterchangeError.invalid("This exchange is outside your sharing permission.")
        }
    }
}

public extension ExchangeSession {
    func prompt(permission: ExchangePermission) async throws -> String {
        try permission.require(appID: configuration.appID, source: permission.source)
        return try await prompt(source: permission.source, sharing: permission.exportIDs)
    }
    func preview(_ data: Data, permission: ExchangePermission) async throws -> ImportPlan<Payload> {
        let batch = try configuration.decode(data)
        try permission.require(appID: configuration.appID, source: batch.source, importing: true)
        return try await preview(data)
    }
    @discardableResult
    func apply(_ plan: ImportPlan<Payload>, selecting ids: Set<String>, permission: ExchangePermission) async throws -> Int {
        try permission.require(appID: configuration.appID, source: plan.batch.source, importing: true)
        return try await apply(plan, selecting: ids)
    }
}
