import Testing
import NativeSecurity

@Test func staleAuthenticationAndReplayedSuccessCannotUnlock() {
    var gate = AuthenticationGate(enabled: true)
    let stale = gate.beginAuthentication()
    gate.lock()
    let staleAccepted = gate.authenticationSucceeded(.unlock, attempt: stale)
    #expect(!staleAccepted)
    #expect(gate.isLocked)
    let current = gate.beginAuthentication()
    let accepted = gate.authenticationSucceeded(.unlock, attempt: current)
    let replayAccepted = gate.authenticationSucceeded(.disable, attempt: current)
    #expect(accepted)
    #expect(!replayAccepted)
    #expect(gate.enabled && gate.unlocked)
}
