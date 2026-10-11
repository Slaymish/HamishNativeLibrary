/// A per-device UI gate, not encryption or a replacement for LocalAuthentication.
/// The host supplies an actual OS authentication result; stale callbacks cannot unlock a newer session.
public struct AuthenticationGate: Sendable {
    public enum Intent: Sendable { case unlock, enable, disable }
    public private(set) var enabled: Bool
    public private(set) var unlocked = false
    private var generation: UInt64 = 0
    public init(enabled: Bool) { self.enabled = enabled }
    public var isLocked: Bool { enabled && !unlocked }
    public mutating func beginAuthentication() -> UInt64 { generation &+= 1; return generation }
    @discardableResult public mutating func authenticationSucceeded(_ intent: Intent, attempt: UInt64) -> Bool {
        guard attempt == generation else { return false }
        switch intent {
        case .enable: enabled = true; unlocked = true
        case .disable: enabled = false; unlocked = false
        case .unlock: guard enabled else { return false }; unlocked = true
        }
        generation &+= 1
        return true
    }
    public mutating func lock() { generation &+= 1; unlocked = false }
}
