---
name: release
description: Prepare and release HamishNativeLibrary source versions using the City-style changelog, checks, annotated tag and watched GitHub CI process. Use for this library's releases, not consumer app publication.
---

# Release HamishNativeLibrary

Read `docs/RELEASING.md` and `docs/ADOPTION.md`. This is a source package release; Sparkle belongs to
consuming macOS apps. The tag workflow creates a draft. Publishing the library does not update installed apps.

Determine the authorised scope before remote mutation. Complete local preparation and show the actual
version, notes and checks before any required publication approval. If tagging/pushing/publishing has already
been explicitly authorised, proceed within that authorisation without asking again.

Inspect status, branch, remote and latest version tag. Preserve unrelated changes. Use Slaymish gh credentials
per command rather than switching the machine's default account. Fetch tags before comparing versions.
Release clean, pushed main whose exact commit has green CI. Stop on failed checks; diagnose locally and fix
forward. Do not reuse a published tag or overwrite release assets.

Prepare notes from changes since the previous tag, reading the relevant diff. Describe behavior/API changes,
schema migrations and minimum platform changes useful to consuming app maintainers. Update `VERSION` and a
dated `CHANGELOG.md` section. Before 1.0, compatible fixes bump patch; breaking changes bump minor. Respect an
explicit user version when valid and greater than the previous release.

Run `scripts/check.sh`, `scripts/check-platforms.sh`, and `swift build --package-path Examples/MacUpdater`.
Run `scripts/check-release.py VERSION` to extract/validate the exact notes. Commit only intended library files.
For an authorised release, create an annotated `vVERSION` tag and push main/tag atomically. Watch the
`Library release` workflow to completion; inspect the draft notes and tag. Publish only within the user's
authorisation. Verify the release URL and exact tag, then report consumer upgrade steps.

If the remote repo is absent, complete local preparation and identify the intended repository name and
visibility needed for creation. Do not invent a live repository or change credentials. Keep signing secrets
and real app data out of this package. No remote tag/push/release is implied by “GitHub-ready” setup alone.
