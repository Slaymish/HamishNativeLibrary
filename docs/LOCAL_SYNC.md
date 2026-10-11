# Automatic device sync on the same network

`NativeSync` is an opt-in, dependency-free Apple-platform module for private app records. The Mac
hosts an encrypted connection; paired iOS apps discover it through Bonjour, reconnect automatically and
exchange their latest durable state. No iCloud, hosted account, relay, model call or paid Apple capability
is used. This is device data sync, separate from the manual ChatGPT/Claude interchange contract.

## Pairing and everyday use

Keep Close: open Preferences → Device sync on the Mac, enable sharing, copy the pairing code and
paste it into the same screen on the iPhone. Existing records on both devices are retained. All relationship
fields, contact history, plans, context and dismissal state, requested reminder preferences, and provider
checkpoints participate. OS permission/scheduling status, app locks, backups, local identities and keys do
not. Permission to show notification names still needs configuring independently on each device.

City: retain Settings → iPhone and its existing QR pairing code. The shared transport preserves its
service name, key identifiers, PSK derivation and signed command protocol. The phone now keeps a durable,
host-and-key-bound city copy, and More → Synced information exposes the journal, floor history, totals,
queue text and portable configuration. City remains a Mac-hosted runtime: requests/answers travel back
through its existing signed, replay-checked commands. Credentials, local repository files, config paths,
raw CLI logs, tool permissions and OS/device preferences are not copied into a phone database. There is
no offline queue for approvals or job commands. Cached questions can be stale and the Mac still verifies
that each one is pending. This is an authoritative Mac mirror, not symmetric independent execution.

Keep the Mac awake, with the app open. Open the iPhone app while both devices can reach each other.
iOS suspends ordinary apps in the background; continuous closed-app sync is not provided. Edits persist
offline and exchange after foreground reconnect. Guest Wi-Fi isolation, firewalls, denied Local Network
permission, a sleeping Mac or an app closed on either device can prevent transfer. Internet-only sync
would need a separate server/relay design. Apple's peer-to-peer support is enabled as a convenience,
not a guarantee of discovery across routers or without Wi-Fi.

[Apple local-network privacy requirements](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
and [iOS background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time).
A free personal Xcode provisioning route still has its own installation/signing limitations; this module
is not an iOS distribution channel. See [release constraints](RELEASING.md).

## Integrate a new app

Add the `NativeSync` product; add `NativeUI` if using `SyncSettingsView`. Implement `LocalSyncRepository`
in the app repository. Use `SyncJournal` **under the existing exclusive app/CLI lock**, not another
uncoordinated database or a shared cloud folder. A minimal implementation is shown in
[the compiled journal example](../Examples/LocalSyncSmoke/Sources/SyncSmoke/ExampleRepository.swift).

- Export stable record IDs and canonical Codable payloads from `readCurrent`. Include only the agreed
  portable data. Never include pairing keys, app lock flags, access grants or local notification status.
- Validate every projected app record before writing the journal. Reject unsupported fields/versions,
  wrong IDs, duplicate identities and invalid domain values rather than dropping unknown data.
- `apply` must validate again, then idempotently write/remove app files. Preserve changed originals in
  private backups. Run `recover(apply:)` before **every** normal read/write under that same lock.
- Before a normal app/CLI write call `validateEdit(proposedProjection)` under the lock. It blocks changes
  to unresolved records, retaining alternatives until explicit review. Preflight multi-record changes
  before writing any constituent file.
- Expose `join`, `exchange` and `resolve` through the repository protocol. Initialise `SyncService` with
  a versioned app namespace, app-specific Bonjour type and that repository. Set NSBonjourServices to
  that type and NSLocalNetworkUsageDescription to the actual purpose. Start in the foreground; stop on
  iOS background. No multicast entitlement or CloudKit container is required for this ordinary Bonjour/TCP path.
- Enable hosting/pairing only on explicit user action. The default credential store uses per-device
  Keychain items; tests inject `SyncCredentials` instead of accessing real Keychain entries.
- Show `SyncSettingsView` with app-specific record titles and **full** readable version descriptions.
  Disable consequential actions on cached/offline runtime state. Handle failures without claiming success.

## Merge, deletion and recovery

Vector clocks represent causal edits; wall-clock time does not decide winners. Different record IDs union.
Given a shared ancestor, independent JSON fields and arrays of objects with stable unique string `id`s
merge automatically. Array order follows the shared order, then new IDs in stable order. Unkeyed arrays,
competing scalar edits and missing/expired common ancestors require review. Records created independently
with different IDs are separate; the app owns human identity matching and explicit deduplication.

All concurrent whole-record versions remain in the journal. The app shows a deterministic provisional
projection while conflicts are pending. Concurrent delete/edit displays the deletion and retains the edit
for review. Choosing a version explicitly replaces the **whole record**, including fields that had merged;
it creates a new causal revision that dominates the alternatives. Local edits cannot silently absorb an
unreviewed conflict. Replayed older states cannot resurrect a causal deletion. Tombstones are retained;
there is no automatic pruning that would allow a long-offline device to bring deleted records back.

The journal writes a private `.pending` transaction before applying domain files, then advances committed
sync metadata and removes pending. Interrupted writes recover idempotently before other app/CLI work.
Only a completed domain write is returned/sent as success. `validate` runs before pending is created, so
invalid incoming domain data cannot poison recovery. An already accepted transaction may finish after
disconnect/background; lifecycle generations prevent old connections from sharing a newly paired group's data.

Limits: 32 MiB encoded replica, 8 MiB per payload, 10,000 IDs, 16 lifetime device identities, 32 concurrent
versions and 16 ancestors per version. Tombstones/history contribute to the limit. Exceeding limits fails
explicitly without discarding data. Many offline edits can exhaust common ancestry and require whole-record
review. This is suitable for small personal app stores, not large files, CRDT text editing or unlimited teams.
Both peers must understand the same namespace and payload versions. Implement deliberate migrations when
those contracts change. Never reset journal metadata merely to clear an error or start from empty data.

## Security and verification

TLS 1.2 PSK with AES-128-GCM uses a random 256-bit pairing secret and app-separated HMAC derivation.
Resumption and session tickets are disabled: every new connection proves the currently configured key,
including after rotation. A wrong-key regression test follows a successful authenticated connection.
Connections have a handshake deadline, bounded frames/queues and limited peers. Listener/browser callbacks
from cancelled generations are discarded, and discovery retries do not require Bonjour results to change.
There is no unauthenticated plaintext fallback or certificate verification bypass. Bonjour advertisements
are discovery hints; key possession provides authentication. Pairing codes confer full read/write access
on reachable networks, so treat them as passwords and share only with trusted devices.

Each app has its own pair/group. Copying a key or application database manually is not a pairing workflow.
Disconnecting stops future transfers and removes that device's credential; it cannot retract copies,
backups or exports already shared. To revoke another Keep Close device, disconnect/re-enable on the host
and re-pair trusted devices; City retains Pair Again. Local JSON, histories, backups and caches are private
files but not encrypted at rest by this module. App lock is a screen gate. Protect the device itself.

Checks use fictional records, temporary directories, disposable in-memory secrets, fragmentation and
malformed-frame tests, divergent offline versions, tombstones, explicit conflict resolution, journal recovery,
semantic rejection and real authenticated loopback TCP. The loopback example never advertises Bonjour or
reads production credentials. Mac/iOS builds verify the integration. A real paired phone, permission
prompts, sleep/wake, guest Wi-Fi and locked-device Keychain behavior still require device testing before
an app release. Unit tests and loopback cannot establish that physical-device experience.
