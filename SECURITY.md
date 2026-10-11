# Security and privacy

Imports are untrusted data. Validation is strict and bounded; no payload executes commands, opens URLs,
runs tools or changes permissions. Prompt injection text can still influence the receiving model: prompt
instructions are guidance, not a security boundary. Host apps must never turn model text into shell actions.

Consent is explicit. Share only a narrow payload and chosen record IDs. The UI shows full exchanged values
for review and starts every import unchecked. Local app consent does not grant provider memory access.
The app must persist and enforce its current permission, including revocation, at each operation. The base
session APIs remain useful for explicit one-off actions and do not impose an authentication system.

Data, provider checkpoints, receipts and backups are local JSON. File permissions are private; this is not
encryption. Device/app authentication is not encryption either. Keep secrets in NativeSecurity's Keychain
store, not in the payload or prompts. Keychain records are per device, non-synchronising and available when
unlocked. Credentials are not automatically cleared when a user revokes a manual exchange permission.

Atomic replacement and advisory file locks cover cooperating local app/CLI writers using the same path.
Corruption and read errors are surfaced, never silently overwritten with an empty store. Use a trusted
app-private path, not an untrusted imported path or shared writable directory. Backups accumulate and may
contain old/deleted context; host apps need a retention policy. Do not log prompts, imported payloads,
relationship data, credentials or backup contents. Tests use fictional records and isolated temporary paths.

Stable IDs prevent accidental renaming duplicates, but the host still owns real-world identity matching,
protected preferences, history, dismissal semantics and consequential decisions. Whole-payload replacement
requires review. Exclude transactions, contact history, access permissions and other authority-bearing state
from a generic agent exchange. Apps with separate databases must integrate their actual transaction boundary.

Sparkle signature checks do not replace Apple notarisation or Gatekeeper. Never commit keys, private
exports or real app data, and never reuse another app's private update key. App distribution requires
testing an actual prior installation, not just this package's test results. See docs/RELEASING.md.

This repository has no security-report inbox configured. Before public hosting, configure a private
reporting channel or enable GitHub private vulnerability reporting. Do not put a private-data sample
into a public issue.
