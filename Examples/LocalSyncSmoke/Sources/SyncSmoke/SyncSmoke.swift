import Foundation
@preconcurrency import Network
import NativeSync

@main struct SyncSmoke {
    enum Failure: Error { case listener, delivery, authentication }
    /// Real encrypted TCP on loopback, no Bonjour registration, production keys, or personal data.
    @MainActor static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Sync smoke check failed.\n".utf8)); exit(1) }
    }
    @MainActor static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FictionalSync-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = ExampleRepository(directory: directory.appendingPathComponent("Mac"))
        let b = ExampleRepository(directory: directory.appendingPathComponent("Phone"))
        let group = UUID(), id = UUID()
        try a.edit(id: id, note: .init(title: "Fictional note", note: "Original"))
        _ = try b.joinSync(groupID: group)
        _ = try b.exchangeSync(groupID: group, remote: a.joinSync(groupID: group))
        try a.edit(id: id, note: .init(title: "Mac title", note: "Original"))
        try b.edit(id: id, note: .init(title: "Fictional note", note: "Phone note"))
        let merged = try a.exchangeSync(groupID: group, remote: b.exchangeSync(groupID: group, remote: nil))
        guard merged.conflicts.isEmpty else { throw Failure.delivery }
        print("Offline fictional notes merged through the locked app repository.")
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
        guard let port = listener.port else { throw Failure.listener }
        let correct = LocalConnection<String>(NWConnection(host: "localhost", port: port, using: parameters(key)))
        correct.onReady = { correct.send("fictional data") }
        correct.start(); defer { correct.close() }
        for _ in 0..<200 where received.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        guard received == ["fictional data"] else { print("Transport state: \(correct.connection.state)"); throw Failure.delivery }
        var wrongClosed = false, wrongReady = false
        let wrong = LocalConnection<String>(NWConnection(host: "localhost", port: port, using: parameters(Data(repeating: 18, count: 32))))
        wrong.onReady = { wrongReady = true; wrong.send("must not arrive") }
        wrong.onClose = { wrongClosed = true }
        wrong.start(); defer { wrong.close() }
        for _ in 0..<600 where !wrongClosed { try await Task.sleep(for: .milliseconds(20)) }
        guard wrongClosed && !wrongReady && received == ["fictional data"] else { throw Failure.authentication }
        print("Encrypted loopback delivered fictional data and rejected an unpaired key.")
    }
}
