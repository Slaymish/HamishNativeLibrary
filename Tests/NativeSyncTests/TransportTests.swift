import Foundation
import Testing
@preconcurrency import Network
import NativeSync

struct TransportTests {
    /// Real encrypted TCP on loopback, no Bonjour registration, production keys, or personal data.
    @Test @MainActor func authenticatedLoopbackDeliversFramesAndRejectsAnotherKey() async throws {
        let key = Data(repeating: 17, count: 32)
        func parameters(_ key: Data) -> NWParameters {
            let p = LocalTLS.parameters(key: key, domain: "fictional-test", identity: "fictional-test")
            p.includePeerToPeer = false
            return p
        }
        let listener = LocalListener<String>()
        var received: [String] = [], servers: [LocalConnection<String>] = []
        listener.onConnection = { link in servers.append(link); link.onMessage = { received.append($0) } }
        try listener.start(parameters: parameters(key), name: "test", serviceType: nil, hostID: UUID())
        defer { listener.stop(); servers.forEach { $0.close() } }
        for _ in 0..<100 where listener.port == nil { try await Task.sleep(for: .milliseconds(20)) }
        let port = try #require(listener.port)
        let correct = LocalConnection<String>(NWConnection(host: "localhost", port: port, using: parameters(key)))
        correct.onReady = { correct.send("fictional data") }
        correct.start(); defer { correct.close() }
        for _ in 0..<200 where received.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(received == ["fictional data"], "Client: \(correct.connection.state), servers: \(servers.map { String(describing: $0.connection.state) })")
        var wrongClosed = false, wrongReady = false
        let wrong = LocalConnection<String>(NWConnection(host: "localhost", port: port, using: parameters(Data(repeating: 18, count: 32))))
        wrong.onReady = { wrongReady = true; wrong.send("must not arrive") }
        wrong.onClose = { wrongClosed = true }
        wrong.start(); defer { wrong.close() }
        for _ in 0..<600 where !wrongClosed { try await Task.sleep(for: .milliseconds(20)) }
        #expect(wrongClosed && !wrongReady && received == ["fictional data"], "Unpaired client state: \(wrong.connection.state)")
    }
}
