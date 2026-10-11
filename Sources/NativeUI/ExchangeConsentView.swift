import SwiftUI
import AgentInterchange

/// Host app persists/revokes the returned permission and uses permission-aware session APIs.
@MainActor public struct ExchangeConsentView: View {
    private let appID: String
    private let source: String
    private let records: [ConsentRecord]
    private let onApprove: (ExchangePermission) -> Void
    @State private var selected: Set<String> = []
    @State private var imports = false

    public struct ConsentRecord: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public init(id: String, title: String, detail: String) {
            self.id = id; self.title = title; self.detail = detail
        }
    }

    public init(appID: String, source: String, records: [ConsentRecord],
                onApprove: @escaping (ExchangePermission) -> Void) {
        self.appID = appID; self.source = source; self.records = records; self.onApprove = onApprove
    }
    public var body: some View {
        Form {
            Section("Choose what to share") {
                Text("Share selected app context with \(source) by copying or sharing a prompt. Nothing is sent in the background.")
                ForEach(records) { record in
                    Toggle(isOn: Binding(get: { selected.contains(record.id) }, set: { enabled in
                        if enabled { selected.insert(record.id) } else { selected.remove(record.id) }
                    })) {
                        VStack(alignment: .leading) { Text(record.title); Text(record.detail).font(.caption) }
                    }
                }
            }
            Section("Choose what can come back") {
                Toggle("Let me review and import suggestions", isOn: $imports)
                Text("Every change needs your review. Conflicting user corrections stay visible.").font(.caption)
            }
            Section {
                Text("This enables a manual handover. It does not sign you in or grant access to agent memory or chat history.")
                Text("You can revoke this app's sharing permission later. Information already shared stays with the receiving service until you remove it there.").font(.caption)
                Button("Enable manual exchange") {
                    onApprove(ExchangePermission(appID: appID, source: source,
                        exportIDs: selected, allowsReviewedImports: imports))
                }.disabled(selected.isEmpty && !imports)
            }
        }.navigationTitle("Sharing permission")
    }
}
