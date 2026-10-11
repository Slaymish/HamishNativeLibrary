import SwiftUI
import NativeSync

/// A reusable, explicit pairing and conflict-review screen. Apps supply readable descriptions of their records.
@MainActor public struct SyncSettingsView: View {
    @ObservedObject private var service: SyncService
    private let recordTitle: (String) -> String
    private let versionDescription: (SyncVersion) -> String
    @State private var code = ""
    @State private var busy = false
    public init(service: SyncService, recordTitle: @escaping (String) -> String = { $0 },
                versionDescription: @escaping (SyncVersion) -> String = { $0.payload == nil ? "Deleted record" : "Saved version" }) {
        self.service = service; self.recordTitle = recordTitle; self.versionDescription = versionDescription
    }
    public var body: some View {
        Form {
            Section("Device sync") {
                Text(service.status)
                Text("Your paired devices exchange this app's shared data over an encrypted connection. Keep the Mac awake with the app open, and open the iPhone app on the same network. Changes made offline sync when they reconnect.")
                if let date = service.lastSynced { Text("Last received update: \(date.formatted())").font(.caption) }
                if let failure = service.failure { Text(failure).foregroundStyle(.secondary) }
            }
            if !service.isEnabled {
                Section("Pair your devices") {
                    Text("Pairing shares all of this app's syncable records with the other device. Both devices' existing records are kept; conflicting edits need your review.")
                    #if os(macOS)
                    Button("Enable sharing on this Mac") { perform { await service.enableHost() } }.disabled(busy)
                    #else
                    TextField("Pairing code from your Mac", text: $code, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Pair with Mac") { perform { await service.pair(code: code); code = "" } }.disabled(busy || code.isEmpty)
                    #endif
                }
            } else {
                if let pairingCode = service.pairingCode {
                    Section("Pair an iPhone") {
                        Text("Copy this code to your iPhone's Device sync screen. Treat it like a password: anyone with it can read and change the shared data while on a reachable network.")
                        Button("Copy pairing code") { NativeClipboard.copy(pairingCode) }
                    }
                }
                Section {
                    Text("App locks, operating-system permissions and pairing keys stay on each device. Disconnecting stops future sync; copies already shared remain on the other device.")
                    Button("Disconnect this device", role: .destructive) { service.disconnect() }
                }
            }
            ForEach(service.conflicts) { conflict in
                Section("Review: \(recordTitle(conflict.id))") {
                    Text("Different offline edits were retained. Choosing a version replaces this entire record, including fields that had merged automatically. Review both before choosing.")
                    Text("Conflicting fields: " + conflict.fields.joined(separator: ", ")).font(.caption)
                    ForEach(conflict.versions) { version in
                        VStack(alignment: .leading) {
                            Text(versionDescription(version)).textSelection(.enabled)
                            Text("Edited \(version.editedAt.formatted()) · device \(version.deviceID.prefix(8))").font(.caption)
                            Button(version.payload == nil ? "Keep deletion" : "Use this version") {
                                perform { await service.resolve(record: conflict.id, versionID: version.id) }
                            }.disabled(busy)
                        }
                    }
                }
            }
        }.formStyle(.grouped).navigationTitle("Device sync")
            .task { await service.refreshStoredState() }
    }
    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        busy = true
        Task { await operation(); busy = false }
    }
}
