import SwiftUI
import AgentInterchange
import NativeCore
import NativeUI

struct ReadingPreference: Codable, Equatable, Sendable {
    var topic: String
    var depth: String
}

@main
struct DemoApp: App {
    @State private var session: ExchangeSession<ReadingPreference>?
    @State private var error: String?
    @State private var permission: ExchangePermission?
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let session {
                    if let permission {
                        VStack {
                            Button("Revoke sharing permission") { self.permission = nil }
                            AgentExchangeView(session: session, permission: permission) { $0.topic }
                                .id(permission.approvedAt)
                        }
                    } else {
                        ExchangeConsentView(appID: session.configuration.appID, source: "chatgpt", records: [
                            .init(id: "fictional-reader", title: "Fictional reading preference", detail: "Topic, depth and explicit edits")
                        ]) { self.permission = $0 }
                    }
                } else if let error { Text(error) }
                else { ProgressView().task { await prepare() } }
            }
        }
    }
    @MainActor private func prepare() async {
        do {
            let config = try ExchangeConfiguration<ReadingPreference>(
                appID: "nz.hamish.native-demo", schemaID: "reading", purpose: "Suggest reading preferences.",
                payloadSchema: .object(properties: ["topic": .string(maximum: 120),
                    "depth": .string(maximum: 20, choices: ["brief", "detailed"])], required: ["topic", "depth"]))
            let url = try AppDirectories.applicationSupport(appID: config.appID).appendingPathComponent("exchange.json")
            let exchange = ExchangeSession(configuration: config, stateURL: url)
            if try await exchange.state().records.isEmpty {
                try await exchange.edit(id: "fictional-reader", payload: ReadingPreference(topic: "Ecology", depth: "brief"))
            }
            session = exchange
        } catch { self.error = error.localizedDescription }
    }
}
