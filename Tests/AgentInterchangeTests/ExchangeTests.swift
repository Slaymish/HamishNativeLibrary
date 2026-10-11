import Foundation
import Testing
import AgentInterchange
import NativeCore

struct Preference: Codable, Equatable, Sendable { var name: String; var enabled: Bool }

struct ExchangeTests {
    @Test func existingEnvelopesUseStrictSharedDecoder() throws {
        struct Legacy: Decodable { var version: Int; var people: [Person] }
        struct Person: Decodable { var name: String; var notes: String? }
        let schema = PayloadSchema.object(properties: ["version": .integer(minimum: 1, maximum: 2),
            "people": .array(items: .object(properties: ["name": .string(maximum: 20),
                "notes": .nullable(.string(maximum: 40))], required: ["name"]), maximum: 10)], required: ["version", "people"])
        let text = #"{"version":2,"people":[{"name":"Fictional","notes":null}]}"#
        let good = try StrictJSONDocument.decode(Legacy.self, from: Data(("```\n" + text + "\n```").utf8),
            schema: schema, fences: .jsonOrUnlabelled)
        #expect(good.people.first?.name == "Fictional")
        #expect(throws: (any Error).self) {
            try StrictJSONDocument.decode(Legacy.self, from: Data(text.replacingOccurrences(of: "\"notes\":null", with: "\"history\":[]").utf8), schema: schema)
        }
    }
    @Test func permissionScopesAndRevocation() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let session = ExchangeSession(configuration: try config(), stateURL: folder.appendingPathComponent("state.json"))
        try await session.edit(id: "a", payload: Preference(name: "Shared", enabled: true))
        try await session.edit(id: "private", payload: Preference(name: "Secret-marker", enabled: true))
        var permission = ExchangePermission(appID: "demo", source: "chatgpt", exportIDs: ["a"], allowsReviewedImports: false)
        #expect(!(try await session.prompt(permission: permission)).contains("Secret-marker"))
        let data = try NativeJSON.encode(batch([record("b")]))
        await #expect(throws: (any Error).self) { try await session.preview(data, permission: permission) }
        permission = ExchangePermission(appID: "demo", source: "chatgpt", exportIDs: [], allowsReviewedImports: true)
        let plan = try await session.preview(data, permission: permission)
        permission.revokedAt = Date()
        await #expect(throws: (any Error).self) { try await session.apply(plan, selecting: ["b"], permission: permission) }
        await #expect(throws: (any Error).self) { try await session.prompt(permission: permission) }
        let wrongSource = ExchangePermission(appID: "demo", source: "claude", exportIDs: [], allowsReviewedImports: true)
        await #expect(throws: (any Error).self) { try await session.preview(data, permission: wrongSource) }
    }

    @Test func invalidSchemaDefinitionRejected() throws {
        #expect(throws: (any Error).self) {
            try ExchangeConfiguration<Preference>(appID: "demo", schemaID: "test", purpose: "",
                payloadSchema: .object(properties: [:], required: ["missing"]))
        }
    }
    func config(maximumBytes: Int = 2_000_000) throws -> ExchangeConfiguration<Preference> {
        try ExchangeConfiguration(appID: "demo", schemaID: "preferences", purpose: "Configure fictional preferences.",
            payloadSchema: .object(properties: ["name": .string(maximum: 100), "enabled": .boolean],
                required: ["name", "enabled"]), maximumBytes: maximumBytes)
    }
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func batch(_ records: [ProposedRecord<Preference>], id: String = UUID().uuidString,
               source: String = "chatgpt") -> ExchangeBatch<Preference> {
        ExchangeBatch(appID: "demo", schemaID: "preferences", exchangeID: id, source: source, records: records)
    }
    func record(_ id: String = "a", _ name: String = "Fictional", base: Int? = nil,
                confidence: Confidence? = nil) -> ProposedRecord<Preference> {
        ProposedRecord(id: id, baseRevision: base, payload: Preference(name: name, enabled: true), confidence: confidence)
    }

    @Test func strictEnvelopeAndPayloadValidation() throws {
        let configuration = try config()
        let good = try NativeJSON.encode(batch([record()]))
        var object = try JSONSerialization.jsonObject(with: good) as! [String: Any]
        object["unexpected"] = true
        #expect(throws: (any Error).self) { try configuration.decode(JSONSerialization.data(withJSONObject: object)) }
        object.removeValue(forKey: "unexpected")
        var records = object["records"] as! [[String: Any]]
        var payload = records[0]["payload"] as! [String: Any]
        payload["contactHistory"] = []
        records[0]["payload"] = payload; object["records"] = records
        #expect(throws: (any Error).self) { try configuration.decode(JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func wrongVersionProviderDuplicatesAndConfidenceRejected() throws {
        let configuration = try config()
        var wrong = batch([record()]); wrong.schemaVersion = 2
        #expect(throws: (any Error).self) { try configuration.decode(NativeJSON.encode(wrong)) }
        wrong = batch([record()]); wrong.appID = "other-app"
        #expect(throws: (any Error).self) { try configuration.decode(NativeJSON.encode(wrong)) }
        #expect(throws: (any Error).self) { try configuration.decode(NativeJSON.encode(batch([record(), record()]))) }
        #expect(throws: (any Error).self) { try configuration.decode(NativeJSON.encode(batch([record()], source: "unknown"))) }
        #expect(throws: (any Error).self) { try configuration.decode(NativeJSON.encode(batch([record(confidence: .userConfirmed)]))) }
        #expect(throws: (any Error).self) { try configuration.decode(NativeJSON.encode(batch([record(" ")]))) }
    }

    @Test func boundedInputAndWholeFenceOnly() throws {
        let good = try NativeJSON.encode(batch([record()]))
        #expect(throws: (any Error).self) { try config(maximumBytes: 10).decode(good) }
        let fenced = Data(("```json\n" + String(decoding: good, as: UTF8.self) + "\n```").utf8)
        #expect(try config().decode(fenced).records.count == 1)
        #expect(throws: (any Error).self) { try config().decode(Data(("Here is JSON: " + String(decoding: good, as: UTF8.self)).utf8)) }
    }

    @Test func schemaDistinguishesBooleanIntegerAndLimits() throws {
        let integer = PayloadSchema.integer(minimum: 0, maximum: 10)
        #expect(throws: (any Error).self) { try integer.validate(.bool(true)) }
        #expect(throws: (any Error).self) { try integer.validate(.number(1.5)) }
        #expect(throws: (any Error).self) { try PayloadSchema.array(items: .boolean, maximum: 1).validate(.array([.bool(true), .bool(false)])) }
        #expect(throws: (any Error).self) { try PayloadSchema.string(maximum: 2).validate(.string("long")) }
        try PayloadSchema.nullable(.boolean).validate(.null)
    }

    @Test func previewSelectionProvenanceAndReplayAreDurable() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("state.json")
        let session = ExchangeSession(configuration: try config(), stateURL: url)
        let data = try NativeJSON.encode(batch([record("a"), record("b", "Other")], id: "batch-1"))
        let plan = try await session.preview(data)
        #expect(try await session.state().records.isEmpty)
        #expect(plan.items.allSatisfy { $0.action == .add })
        #expect(try await session.apply(plan, selecting: ["a"]) == 1)
        let reopened = ExchangeSession(configuration: try config(), stateURL: url)
        let state = try await reopened.state()
        #expect(state.records["a"]?.confidence == .suggested)
        #expect(state.records["b"] == nil)
        #expect(try await reopened.preview(data).alreadyApplied)
        let altered = try NativeJSON.encode(batch([record("a", "Changed")], id: "batch-1"))
        await #expect(throws: (any Error).self) { try await reopened.preview(altered) }
    }

    @Test func userCorrectionConflictAndStalePreviewPreventOverwrite() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let session = ExchangeSession(configuration: try config(), stateURL: folder.appendingPathComponent("state.json"))
        try await session.edit(id: "a", payload: Preference(name: "Corrected", enabled: true))
        let plan = try await session.preview(NativeJSON.encode(batch([record("a", "Older", base: 1)])))
        #expect(plan.items[0].action == .conflict)
        try await session.edit(id: "a", payload: Preference(name: "New correction", enabled: true))
        await #expect(throws: InterchangeError.self) { try await session.apply(plan, selecting: ["a"]) }
        #expect(try await session.state().records["a"]?.payload.name == "New correction")
    }

    @Test func tombstonesAndMissingIdentitiesCannotBeImported() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let session = ExchangeSession(configuration: try config(), stateURL: folder.appendingPathComponent("state.json"))
        try await session.delete(id: "a")
        let plan = try await session.preview(NativeJSON.encode(batch([record(), record("missing", base: 1)])))
        #expect(plan.items.allSatisfy { $0.action == .blocked })
        await #expect(throws: (any Error).self) { try await session.apply(plan, selecting: ["a"]) }
        #expect(try await session.state().records.isEmpty)
    }

    @Test func scopedPromptDoesNotAdvanceCheckpointAndEmptyApplyDoes() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let session = ExchangeSession(configuration: try config(), stateURL: folder.appendingPathComponent("state.json"))
        try await session.edit(id: "a", payload: Preference(name: "Selected-fiction", enabled: true))
        try await session.edit(id: "private", payload: Preference(name: "Private-marker", enabled: false))
        let prompt = try await session.prompt(source: "chatgpt", sharing: ["a"])
        #expect(prompt.contains("Selected-fiction"))
        #expect(!prompt.contains("Private-marker"))
        #expect(try await session.state().checkpoints.isEmpty)
        let empty = try await session.preview(NativeJSON.encode(batch([])))
        try await session.apply(empty, selecting: [])
        #expect(try await session.state().checkpoints["chatgpt"] != nil)
        #expect(try await session.state().checkpoints["claude"] == nil)
    }

    @Test func repeatedPayloadIsUnchangedAndKeepsUserProvenance() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let session = ExchangeSession(configuration: try config(), stateURL: folder.appendingPathComponent("state.json"))
        try await session.edit(id: "a", payload: Preference(name: "Fictional", enabled: true))
        let plan = try await session.preview(NativeJSON.encode(batch([record()])))
        #expect(plan.items[0].action == .unchanged)
        try await session.apply(plan, selecting: [])
        #expect(try await session.state().records["a"]?.confidence == .userConfirmed)
    }
}
