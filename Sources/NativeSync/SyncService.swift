import Foundation
import Combine
import CryptoKit
@preconcurrency import Network
import NativeCore
import NativeSecurity

public protocol LocalSyncRepository: Sendable {
    func joinSync(groupID: UUID) throws -> SyncReplica
    func exchangeSync(groupID: UUID, remote: SyncReplica?) throws -> SyncReplica
    func resolveSync(record: String, versionID: UUID) throws -> SyncReplica
}

public struct SyncInvitation: Codable, Equatable, Sendable {
    public var version = 1
    public let namespace: String
    public let groupID: UUID
    public let hostID: UUID
    public let key: Data
    public init(namespace: String, groupID: UUID = UUID(), hostID: UUID = UUID(), key: Data) {
        self.namespace = namespace; self.groupID = groupID; self.hostID = hostID; self.key = key
    }
    public var code: String { "hamishsync:" + ((try? NativeJSON.encode(self, formatting: .sortedKeys)) ?? Data()).base64EncodedString() }
    public init(code: String, namespace: String) throws {
        guard code.count <= 2048, code.hasPrefix("hamishsync:"),
              let data = Data(base64Encoded: String(code.dropFirst(11))) else { throw SyncFailure.invalid }
        let invitation = try NativeJSON.decode(Self.self, from: data)
        guard invitation.version == 1, invitation.namespace == namespace, invitation.key.count == 32 else {
            throw SyncFailure.invalid
        }
        self = invitation
    }
}

/// Inject a memory-only credential store in tests. Default implementation uses app-owned per-device Keychain items.
public protocol SyncCredentials: Sendable {
    func read() throws -> Data?
    func save(_ data: Data) throws
    func remove() throws
}
public struct KeychainSyncCredentials: SyncCredentials {
    private let store: KeychainStore
    public init(namespace: String) { store = KeychainStore(service: namespace + ".local-sync") }
    public func read() throws -> Data? { try store.read(account: "pairing") }
    public func save(_ data: Data) throws { try store.write(data, account: "pairing") }
    public func remove() throws { try store.remove(account: "pairing") }
}

public enum SyncMessage: Codable, Sendable { case replica(SyncReplica) }

@MainActor public final class SyncService: ObservableObject {
    @Published public private(set) var status = "Sync is off"
    @Published public private(set) var isEnabled = false
    @Published public private(set) var conflicts: [SyncConflict] = []
    @Published public private(set) var lastSynced: Date?
    @Published public private(set) var failure: String?
    public var pairingCode: String? { settings?.host == true ? settings?.invitation.code : nil }
    public let namespace: String
    private let serviceType: String
    private let repository: any LocalSyncRepository
    private let credentials: any SyncCredentials
    private let listener = LocalListener<SyncMessage>(maximumLength: SyncReplica.maximumMessageBytes + 1024)
    private let browser = LocalBrowser()
    private var links: [ObjectIdentifier: LocalConnection<SyncMessage>] = [:]
    private var lastSent: [ObjectIdentifier: Data] = [:]
    private var task: Task<Void, Never>?
    private var active = false
    private var settings: Settings?
    private var generation = UUID()
    private var configuring = false
    private struct Settings: Codable { var host: Bool; var invitation: SyncInvitation }

    public init(namespace: String, serviceType: String, repository: any LocalSyncRepository,
                credentials: (any SyncCredentials)? = nil) {
        self.namespace = namespace; self.serviceType = serviceType; self.repository = repository
        self.credentials = credentials ?? KeychainSyncCredentials(namespace: namespace)
        do {
            if let data = try self.credentials.read() {
                let saved = try NativeJSON.decode(Settings.self, from: data)
                guard saved.invitation.version == 1, saved.invitation.namespace == namespace, saved.invitation.key.count == 32 else { throw SyncFailure.invalid }
                settings = saved; isEnabled = true; status = "Waiting to reconnect"
            }
        } catch { failure = "Unlock this device to access its saved sync pairing." }
        listener.onConnection = { [weak self] link in self?.adopt(link) }
        listener.onStatus = { [weak self] message in if self?.links.isEmpty == true { self?.status = message } }
        browser.onStatus = { [weak self] message in if self?.links.isEmpty == true { self?.status = message } }
    }

    /// Called only after an explicit user request to enable sharing on this Mac.
    public func enableHost() async {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let next = Settings(host: true, invitation: SyncInvitation(namespace: namespace, key: key))
        await configure(next)
    }
    public func pair(code: String) async {
        do { await configure(Settings(host: false, invitation: try SyncInvitation(code: code.trimmingCharacters(in: .whitespacesAndNewlines), namespace: namespace))) }
        catch { failure = "That pairing code is not valid for this app." }
    }
    private func configure(_ next: Settings) async {
        guard !configuring else { return }
        configuring = true
        defer { configuring = false }
        stop()
        do {
            let previousCredential = try credentials.read()
            try credentials.save(NativeJSON.encode(next))
            let repository = repository
            let state: SyncReplica
            do { state = try await Task.detached { try repository.joinSync(groupID: next.invitation.groupID) }.value }
            catch {
                if let previousCredential { try credentials.save(previousCredential) } else { try credentials.remove() }
                throw error
            }
            settings = next; isEnabled = true; conflicts = state.conflicts; failure = nil
            start()
        } catch { failure = error.localizedDescription }
    }
    public func disconnect() {
        stop()
        do { try credentials.remove(); settings = nil; isEnabled = false; status = "Sync is off"; failure = nil }
        catch { failure = "Could not remove this device's pairing. Try again while it is unlocked." }
    }

    /// Host apps call start on foreground and stop on iOS background. No permanent background service is installed.
    public func start() {
        guard !active, let settings else { return }
        active = true; generation = UUID(); failure = nil
        let invitation = settings.invitation
        let parameters = parameters(invitation)
        if settings.host {
            do { try listener.start(parameters: parameters, name: invitation.hostID.uuidString, serviceType: serviceType, hostID: invitation.hostID) }
            catch { status = "Could not listen on this network"; failure = error.localizedDescription }
        } else {
            status = "Looking for your paired Mac"
            browser.start(hostID: invitation.hostID, parameters: parameters, serviceType: serviceType) { [weak self] endpoint in
                guard let self, self.active, self.links.isEmpty else { return }
                let link = LocalConnection<SyncMessage>(NWConnection(to: endpoint, using: self.parameters(invitation)),
                    maximumLength: SyncReplica.maximumMessageBytes + 1024)
                self.adopt(link); link.start()
            }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.active else { return }
                await self.exchange(nil)
                if self.settings?.host == true { self.listener.retry() }
                if self.links.isEmpty && self.settings?.host == false { self.browser.retry() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    public func stop() {
        active = false; generation = UUID(); task?.cancel(); task = nil
        browser.stop(); listener.stop()
        let old = Array(links.values); links = [:]; lastSent = [:]
        old.forEach { $0.close() }
        if isEnabled { status = "Waiting to reconnect" }
    }
    public func resolve(record: String, versionID: UUID) async {
        let repository = repository
        do {
            let state = try await Task.detached { try repository.resolveSync(record: record, versionID: versionID) }.value
            conflicts = state.conflicts; failure = nil; broadcast(state)
        } catch { failure = error.localizedDescription }
    }
    private func parameters(_ invitation: SyncInvitation) -> NWParameters {
        LocalTLS.parameters(key: invitation.key, domain: "native-sync:" + namespace, identity: namespace)
    }
    private func adopt(_ link: LocalConnection<SyncMessage>) {
        guard active, links.count < 8 else { return link.close() }
        let id = ObjectIdentifier(link); links[id] = link
        let acceptedGeneration = generation
        link.onReady = { [weak self] in Task {
            guard let self, self.generation == acceptedGeneration else { return }
            await self.exchange(nil)
        } }
        link.onMessage = { [weak self] message in
            if case .replica(let remote) = message { Task {
                guard let self, self.generation == acceptedGeneration else { return }
                await self.exchange(remote)
            } }
        }
        link.onFailure = { [weak self] message in self?.failure = message }
        link.onClose = { [weak self] in
            guard let self else { return }
            self.links[id] = nil; self.lastSent[id] = nil
            if self.active && self.links.isEmpty { self.status = "Offline — changes will sync when your Mac reconnects" }
        }
    }
    private func exchange(_ remote: SyncReplica?) async {
        guard active, let groupID = settings?.invitation.groupID else { return }
        let currentGeneration = generation, repository = repository
        do {
            let state = try await Task.detached { try repository.exchangeSync(groupID: groupID, remote: remote) }.value
            guard active, generation == currentGeneration else { return }
            conflicts = state.conflicts; failure = nil
            if remote != nil { lastSynced = Date(); status = conflicts.isEmpty ? "Up to date on this network" : "Changes synced — review conflicting edits" }
            broadcast(state)
        } catch { if active && generation == currentGeneration { failure = error.localizedDescription } }
    }
    private func broadcast(_ state: SyncReplica) {
        guard let bytes = try? NativeJSON.encode(state) else { return }
        let digest = Data(SHA256.hash(data: bytes))
        for (id, link) in links where lastSent[id] != digest {
            lastSent[id] = digest; link.sendLatest(.replica(state))
        }
    }
}
