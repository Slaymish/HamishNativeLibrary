import SwiftUI
import UniformTypeIdentifiers
import AgentInterchange
import NativeCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public struct AgentExchangeView<Payload: Codable & Equatable & Sendable>: View {
    private let session: ExchangeSession<Payload>
    private let source: String
    private let sharing: Set<String>
    private let title: (Payload) -> String
    private let permission: ExchangePermission?
    @State private var prompt = ""
    @State private var input = ""
    @State private var plan: ImportPlan<Payload>?
    @State private var selection: Set<String> = []
    @State private var choosingFile = false
    @State private var message: String?
    @State private var busy = false

    public init(session: ExchangeSession<Payload>, source: String = "chatgpt",
                sharing ids: Set<String>, title: @escaping (Payload) -> String) {
        self.session = session; self.source = source; self.sharing = ids; self.title = title
        self.permission = nil
    }

    public init(session: ExchangeSession<Payload>, permission: ExchangePermission,
                title: @escaping (Payload) -> String) {
        self.session = session; self.source = permission.source; self.sharing = permission.exportIDs
        self.title = title; self.permission = permission
    }

    public var body: some View {
        Form {
            Section("Share selected context") {
                Text("The prompt includes the selected records and their changes. Review it before sharing with your agent.")
                Button("Copy prompt") { copy() }.disabled(prompt.isEmpty || busy)
                ShareLink("Share prompt…", item: prompt).disabled(prompt.isEmpty || busy)
                DisclosureGroup("Read what will be shared") { Text(prompt).font(.caption).textSelection(.enabled) }
            }
            Section("Bring back suggestions") {
                Button("Choose JSON file…") { choosingFile = true }.disabled(busy || permission?.allowsReviewedImports == false)
                TextEditor(text: $input).frame(minHeight: 120).font(.system(.caption, design: .monospaced))
                    .disabled(busy)
                Button("Preview") { preview(Data(input.utf8)) }.disabled(input.isEmpty || busy || permission?.allowsReviewedImports == false)
            }
            if let plan {
                Section("Review changes") {
                    if plan.alreadyApplied { Text("This batch was already applied.") }
                    ForEach(plan.items) { item in
                        VStack(alignment: .leading) {
                            Toggle("\(title(item.proposed.payload)) · \(item.action.rawValue)", isOn: Binding(
                                get: { selection.contains(item.id) },
                                set: { enabled in if enabled { selection.insert(item.id) } else { selection.remove(item.id) } }
                            )).disabled(!item.canSelect || busy)
                            Text(item.explanation).font(.caption)
                            DisclosureGroup("Compare values") {
                                if let existing = item.existing { Text("Current: \(details(existing.payload))") }
                                Text("Proposed: \(details(item.proposed.payload))")
                            }.font(.caption).textSelection(.enabled)
                        }
                    }
                    Text("Selecting a conflict replaces its shared fields. Accepting does not verify an inferred fact.").font(.caption)
                    Button("Apply selected changes (\(selection.count))") { apply(plan) }
                        .disabled(busy || plan.alreadyApplied)
                }
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .navigationTitle("Exchange with your agent")
        .task { await loadPrompt() }
        .onChange(of: input) { _ in plan = nil; selection = []; message = nil }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                preview(try handle.read(upToCount: session.configuration.maximumBytes + 1) ?? Data())
            } catch { plan = nil; selection = []; message = "Could not read the selected file." }
        }
    }

    private func details(_ payload: Payload) -> String {
        (try? NativeJSON.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? "Could not display value."
    }
    private func loadPrompt() async {
        do {
            if let permission { prompt = try await session.prompt(permission: permission) }
            else { prompt = try await session.prompt(source: source, sharing: sharing) }
        }
        catch { prompt = ""; message = error.localizedDescription }
    }
    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #else
        UIPasteboard.general.string = prompt
        #endif
        message = "Prompt copied. Paste it into a chat you want to share this context with."
    }
    private func preview(_ data: Data) {
        plan = nil; selection = []; message = nil; busy = true
        Task {
            defer { busy = false }
            do {
                if let permission { plan = try await session.preview(data, permission: permission) }
                else { plan = try await session.preview(data) }
                // Every suggestion starts unchecked; conflicts require an explicit choice.
            } catch { message = error.localizedDescription }
        }
    }
    private func apply(_ plan: ImportPlan<Payload>) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let count: Int
                if let permission { count = try await session.apply(plan, selecting: selection, permission: permission) }
                else { count = try await session.apply(plan, selecting: selection) }
                self.plan = nil; selection = []
                await loadPrompt()
                message = "Applied \(count) changes. A local checkpoint was saved; agent memory changes are separate."
            } catch { message = error.localizedDescription }
        }
    }
}
