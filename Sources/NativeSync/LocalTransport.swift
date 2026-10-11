import Foundation
import CryptoKit
import Security
@preconcurrency import Network
import NativeCore

public enum LocalTLS {
    /// TLS 1.2 PSK-GCM, domain-separated from other uses of the pairing key. No certificates or iCloud needed.
    public static func parameters(key: Data, domain: String, identity: String) -> NWParameters {
        precondition(key.count == 32)
        let tls = NWProtocolTLS.Options()
        let secret = HMAC<SHA256>.authenticationCode(for: Data(domain.utf8), using: SymmetricKey(data: key))
        let psk = secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let id = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, psk as __DispatchData, id as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // Every new connection must prove the currently configured key, including after pairing-key rotation.
        sec_protocol_options_set_tls_resumption_enabled(tls.securityProtocolOptions, false)
        sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true; tcp.keepaliveIdle = 10
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

public struct LocalMessageFramer<Message: Codable & Sendable>: Sendable {
    public let maximumLength: Int
    private var buffer = Data()
    public init(maximumLength: Int = SyncReplica.maximumMessageBytes) {
        precondition(maximumLength > 0 && maximumLength <= Int(UInt32.max))
        self.maximumLength = maximumLength
    }
    public func frame(_ message: Message) throws -> Data {
        let data = try NativeJSON.encode(message, formatting: .sortedKeys)
        guard data.count <= maximumLength, data.count <= Int(UInt32.max) else { throw SyncFailure.tooLarge }
        var length = UInt32(data.count).bigEndian
        return Data(bytes: &length, count: 4) + data
    }
    public mutating func feed(_ data: Data) throws -> [Message] {
        // Reads are bounded by the connection; an attacker cannot grow an incomplete frame without limit.
        guard buffer.count + data.count <= maximumLength + 4 + 64 * 1024 else { throw SyncFailure.tooLarge }
        buffer.append(data)
        var messages: [Message] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= maximumLength else { throw SyncFailure.tooLarge }
            guard buffer.count >= 4 + length else { break }
            let body = Data(buffer.dropFirst(4).prefix(length))
            buffer = Data(buffer.dropFirst(4 + length))
            messages.append(try NativeJSON.decode(Message.self, from: body))
        }
        return messages
    }
}

@MainActor public final class LocalConnection<Message: Codable & Sendable> {
    public let connection: NWConnection
    public var onMessage: ((Message) -> Void)?
    public var onReady: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onFailure: ((String) -> Void)?
    private var framer: LocalMessageFramer<Message>
    private var closed = false
    private var sending = false
    private var queue: [Data] = []
    private var latest: Data?
    private var handshake: Task<Void, Never>?

    public init(_ connection: NWConnection, maximumLength: Int = SyncReplica.maximumMessageBytes) {
        self.connection = connection; framer = LocalMessageFramer(maximumLength: maximumLength)
    }
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in Task { @MainActor in self?.changed(state) } }
        connection.start(queue: .main); receive()
        handshake = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.close()
        }
    }
    public func send(_ message: Message) { enqueue(message, coalescing: false) }
    /// Complete state snapshots can coalesce; commands/receipts should use ordered send instead.
    public func sendLatest(_ message: Message) { enqueue(message, coalescing: true) }
    private func enqueue(_ message: Message, coalescing: Bool) {
        guard !closed else { return }
        do {
            let data = try framer.frame(message)
            if coalescing { latest = data }
            else {
                guard queue.count < 32, queue.reduce(0, { $0 + $1.count }) + data.count <= 64 * 1024 * 1024 else {
                    throw SyncFailure.tooLarge
                }
                queue.append(data)
            }
            flush()
        } catch { onFailure?(error.localizedDescription); close() }
    }
    private func flush() {
        guard !sending, !closed else { return }
        let data: Data
        if !queue.isEmpty { data = queue.removeFirst() }
        else if let value = latest { data = value; latest = nil }
        else { return }
        sending = true
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.sending = false
                if error != nil { self.close() } else { self.flush() }
            }
        })
    }
    public func close() {
        guard !closed else { return }
        closed = true; queue = []; latest = nil
        handshake?.cancel(); handshake = nil
        connection.cancel(); onClose?()
    }
    private func changed(_ state: NWConnection.State) {
        switch state {
        case .ready: handshake?.cancel(); handshake = nil; onReady?(); flush()
        case .failed, .cancelled: close()
        case .waiting: close() // The discovery retry reconnects, including after a sleeping host returns.
        default: break
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty {
                    do { for message in try self.framer.feed(data) { if self.closed { break }; self.onMessage?(message) } }
                    catch { self.onFailure?("The connection sent an invalid message."); return self.close() }
                }
                if complete || error != nil { self.close() } else { self.receive() }
            }
        }
    }
}

@MainActor public final class LocalListener<Message: Codable & Sendable> {
    private var listener: NWListener?
    public var onConnection: ((LocalConnection<Message>) -> Void)?
    public var onStatus: ((String) -> Void)?
    public private(set) var isReady = false
    public var port: NWEndpoint.Port? { isReady ? listener?.port : nil }
    private let maximumLength: Int
    private var restart: (() throws -> Void)?
    private var failed = false
    public init(maximumLength: Int = SyncReplica.maximumMessageBytes) { self.maximumLength = maximumLength }
    public func start(parameters: NWParameters, name: String, serviceType: String?, hostID: UUID) throws {
        stop()
        restart = { [weak self] in try self?.start(parameters: parameters, name: name, serviceType: serviceType, hostID: hostID) }
        let listener = try NWListener(using: parameters)
        if let serviceType {
            var txt = NWTXTRecord(); txt["id"] = hostID.uuidString
            listener.service = NWListener.Service(name: name, type: serviceType, domain: nil, txtRecord: txt)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, self.listener === listener else { return }
                switch state {
                case .ready: self.isReady = true; self.onStatus?("Waiting for a paired device")
                case .waiting: self.isReady = false; self.onStatus?("Waiting for local network access")
                case .failed: self.isReady = false; self.failed = true; self.onStatus?("Could not listen on this network")
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor in
                guard let self, self.listener === listener else { return connection.cancel() }
                let link = LocalConnection<Message>(connection, maximumLength: self.maximumLength)
                self.onConnection?(link); link.start()
            }
        }
        listener.start(queue: .main); self.listener = listener
    }
    public func retry() { if failed { try? restart?() } }
    public func stop() { listener?.cancel(); listener = nil; isReady = false; failed = false; restart = nil }
}

@MainActor public final class LocalBrowser {
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var found: (@MainActor (NWEndpoint) -> Void)?
    private var restart: (() -> Void)?
    private var failed = false
    public var onStatus: ((String) -> Void)?
    public init() {}
    public func start(hostID: UUID, parameters: NWParameters, serviceType: String,
                      found: @escaping @MainActor (NWEndpoint) -> Void) {
        stop(); self.found = found
        restart = { [weak self] in self?.start(hostID: hostID, parameters: parameters, serviceType: serviceType, found: found) }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            let match = results.first { result in
                if case .bonjour(let txt) = result.metadata { txt["id"] == hostID.uuidString } else { false }
            }
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                self.endpoint = match?.endpoint
                if let endpoint = match?.endpoint { found(endpoint) }
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                if case .waiting = state { self.onStatus?("Allow Local Network access to find your Mac") }
                if case .failed = state { self.failed = true; self.onStatus?("Could not search this network") }
            }
        }
        browser.start(queue: .main); self.browser = browser
    }
    /// Reconnect even if Bonjour's results have not changed after an interrupted TCP connection.
    public func retry() { if failed { restart?() } else if let endpoint { found?(endpoint) } }
    public func stop() { browser?.cancel(); browser = nil; endpoint = nil; found = nil; restart = nil; failed = false }
}
