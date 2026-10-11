# Existing project investigation

Inspected locally on 11 October 2026. Source repositories were read only.

## The City — primary release reference

`~/Developer/theCity` has a clean working tree. Its `.claude/skills/release/SKILL.md` prepares release
notes from changes since the last tag, requires clean/pushed main and green CI, tags, watches CI and
checks the resulting release/feed. `.github/workflows/ci.yml` builds both platforms and, on a version tag,
packages a ZIP/DMG and uses Sparkle `generate_appcast` to sign archive and feed. The app is configured with
an ad-hoc macOS signing identity (`-`), a public update key, required signed feed and pre-extraction verification.
It does not perform Apple notarisation. Its small updater retains `SPUStandardUpdaterController`.

Hamish reports this process works better than Keep Close's release process and wants future apps to follow
City. This library adopts the skill/tag/CI/feed structure and keeps credential setup separate from release.
It changes account handling to per-command Slaymish credentials, preserving the machine's default gh account.
Initial workflows create reviewable drafts; publishing and a real installed-app update remain explicit steps.

## Keep Close / SocialManager — interchange reference

`~/Developer/SocialManager` has an existing change to `SocialManager.xcodeproj/project.pbxproj`; it was
preserved. Its `docs/RELEASING.md`, release workflow and scripts support two different paths: a Developer ID
notarised CI release with signed feed, and a local self-signed helper that currently omits the appcast.
That latter omission is not carried into the library's update packaging.

`SocialManager/Core/AgentImport.swift` implements strict versioned import, unknown-field rejection,
preview, additive domain merge, recorded uncertainty and provenance. Its prompt includes current records,
changes since the last applied provider checkpoint, deletions and stable UUIDs. Copying does not advance a
checkpoint; applying an empty batch does. `Views/AgentImportView.swift` supports prompt copy, security-scoped
file access, JSON paste, selection and stale-preview handling. Core repository writes are locked and atomic.

The library generalises those mechanics while leaving person matching, contact history, additive notes,
preferences and dismissal matching to each app. It is not a drop-in decoder for Keep Close's version-2 schema.

## Alphero Intelligence — UX intent

`~/Developer/Alphero Intelligence/ideas/import-from-your-agent.md` and the draft/notes in
`drafts/bring-your-own-intelligence/` describe optional selective sharing, bidirectional explicit corrections,
native decisions, provenance, conflict handling, disconnect/undo and protection against feedback loops.
The files distinguish the existing import from proposed ongoing sync. Their strongest proposed test is a
fictional correction making a complete round trip between agent and apps.

This release delivers the local handover and consent primitives, not the draft's proposed background or
cross-app memory sync. No personal relationships, application data, private keys or draft images were copied.
