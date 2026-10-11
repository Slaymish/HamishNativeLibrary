# Data exchange contract

Supply a Codable, Equatable, Sendable payload plus a `PayloadSchema` and optional semantic validation
closure. The schema DSL supports strict objects, bounded arrays/strings, enumerated strings,
bounded integers, booleans and nullable values. It exports JSON Schema-shaped guidance for prompts;
it does not load arbitrary JSON Schema, resolve remote refs or run arbitrary validation code from a file.
Schema versions must match exactly. Add explicit migration in the app before changing them.

For an established app whose envelope and merge rules already work, `StrictJSONDocument.decode` reuses
the same bounded, recursive schema checks without introducing an ExchangeSession database or wire migration.
The app retains domain validation and its own transaction; `SnapshotChanges` can supply stable-ID comparisons
for the existing checkpoint/prompt contract. Keep Close adopts this route.

The envelope has `formatVersion`, `appID`, `schemaID`, `schemaVersion`, `exchangeID`, `source` and
`records`. Each proposed record has an `id`, `payload`, optional `baseRevision`, and optional
`confidence` (`suggested` or `uncertain`). Unknown fields anywhere are rejected. Default limits are
2 MB and 500 records. Source labels and confidence are claims about provenance, not authenticated identity.

`configuration.batchSchema.jsonSchema` produces the contract; `session.prompt` includes an empty
valid response example. A single entire fenced JSON block is accepted, but surrounding prose is not
searched for a plausible object. Failure produces no data writes. App-specific validation runs after
shape validation. Keep error messages free of personal content.

## Round trip

1. Build a narrow exchange payload. Do not use your whole database model with fields hidden by UI.
2. Record user edits with `edit(id:payload:)`. IDs survive name changes; do not match on names alone.
3. Ask the user which records may leave the app. Generate a prompt with those IDs or a permission.
4. Let the user read/share the prompt in their chosen chat. Copying does not advance a checkpoint.
5. Validate and preview the reply. Native UI starts every suggestion unchecked and shows both values.
6. Apply selected IDs against the entire saved preview snapshot. A concurrent edit requires a refresh.
7. On success, store receipts and a per-provider local checkpoint in the same transaction as the records.

The exchange state is a usable store for small apps whose data is precisely this payload. If your app
has a separate domain database, integrate the projection through your app's repository and transaction
boundary. This library does not atomically write two databases. Never advance its receipt/checkpoint and
then silently fail to save the actual domain update. For that integration, adapt the repository transaction
or make the exchange projection your authoritative store for these fields.

## Conflict and replay behavior

- Changed user-confirmed values and missing/stale base revisions are conflicts. Explicitly selecting one
  replaces the whole exchange payload, not individual fields. Use a custom review/merge before importing
  if your app needs additive merging like Keep Close.
- Unchanged payloads keep existing provenance. Agent replies cannot assign `userConfirmed` confidence.
- Tombstoned IDs are blocked. Only the app's explicit `restore(id:)` can allow restoration. An agent can
  invent a fresh ID for the same person/idea; domain identity checks must detect that. The package does
  not prevent semantic rewordings of dismissed ideas as Keep Close's domain-specific matching does.
- A receipt binds provider + exchange ID to canonical content. Same ID/content is an idempotent replay;
  reusing it with different content fails. A fresh ID with unchanged values makes no record changes.
- A partial selection consumes the entire batch, including unselected suggestions. Use a new exchange ID
  for later decisions. An explicitly applied empty batch advances the checkpoint.
- Checkpoints are local boundaries for calculating subsequent app changes, not acknowledgement that
  anything reached a provider or was saved in its memory. Each prompt still includes current selected
  records. Snapshot and receipt history can grow; add app-specific retention without losing tombstones.

## Consent and recovery

`ExchangePermission` is app-side, record-level export consent and permission to review imports. It is
not a signed security token. The app owns storage and revocation and must pass its latest permission to
every operation. Do not keep stale copies after revocation. Replace/dismiss the review view when the
permission changes. A revocation cannot retract information already shared or an operation already
committed. Omit grants entirely if your product does not need saved consent and uses explicit one-off actions.

Imported proposals are saved as suggestions even when accepted; accepting a suggestion is not independent
evidence. Direct user edits set user provenance. Model source labels are not authentication. Prevent loops
by preserving IDs/revisions/provenance and never presenting a reflected suggestion as fresh corroboration.

Backups precede changed writes, under the store's `backups/` folder. For recovery, close all writers,
inspect/validate a chosen backup, and restore it explicitly. Restoring the full exchange state also restores
its checkpoints and receipts. Backups and exports contain personal data and are not encrypted by this package.
