import Foundation
import AgentInterchange
import NativeCore

struct ReadingPreference: Codable, Equatable, Sendable {
    var topic: String
    var depth: String
}

@main
struct Example {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try ExchangeConfiguration<ReadingPreference>(
            appID: "nz.hamish.reading-demo", schemaID: "reading-preference", purpose: "Suggest reading preferences.",
            payloadSchema: .object(properties: ["topic": .string(maximum: 120),
                "depth": .string(maximum: 20, choices: ["brief", "detailed"])], required: ["topic", "depth"]))
        let session = ExchangeSession(configuration: configuration, stateURL: directory.appendingPathComponent("exchange.json"))
        try await session.edit(id: "fictional-reader", payload: ReadingPreference(topic: "Ecology", depth: "brief"))
        let prompt = try await session.prompt(source: "chatgpt", sharing: ["fictional-reader"])
        print("Created a prompt with explicitly selected fictional context (\(prompt.count) characters).")
        let batch = ExchangeBatch(appID: configuration.appID, schemaID: configuration.schemaID, records: [
            ProposedRecord(id: "fictional-reader", baseRevision: 1,
                payload: ReadingPreference(topic: "Ecology", depth: "detailed"), confidence: .uncertain)
        ])
        let plan = try await session.preview(NativeJSON.encode(batch))
        print("Preview: \(plan.items[0].action.rawValue). The user explicitly selects the proposed change.")
        try await session.apply(plan, selecting: ["fictional-reader"])
        let replay = try await session.preview(NativeJSON.encode(batch))
        print("Replay already applied: \(replay.alreadyApplied). No duplicate writes.")
        print("No network calls, memory writes, or real personal data were used.")
    }
}
