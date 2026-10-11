# Setup validation — 11 October 2026

Verified locally with Apple Swift 6.4 and Xcode's macOS/iOS 27 SDKs. Package minimums remain macOS 13/iOS 16;
compilation against those deployment targets does not prove runtime behavior on older OS releases.

- `scripts/check.sh`: passed, including 15 Swift Testing tests, 3 Python tests, the fictional CLI round trip,
  shell syntax and release-note/version validation.
- `scripts/check-platforms.sh`: passed for the native Mac and generic iOS Simulator builds with signing disabled.
  Both produced arm64/x86_64 binaries. No iOS simulator runtime or physical-device run was performed.
- `swift build --package-path Examples/MacUpdater`: passed with Sparkle pinned/resolved to 2.10.0.
- Release integration test: temporary ad-hoc dummy app + disposable Ed25519 key, ZIP integrity/hashes,
  independently verified update signature, signed feed, wrong-key rejection and archive/feed tamper rejection.
  The dummy app does not load Sparkle or exercise the installed updater. Actual update/relaunch testing remains
  required when adopting this in an app.
- Project release skill: bundled skill validator passed with a temporary PyYAML runtime via uv.

CI files were prepared and inspected locally; no GitHub CI run or remote release occurred. Local gh account
verification timed out, so GitHub authentication was not confirmed. No repository visibility was chosen and
no remote was created. VERSION/changelog prepare 0.1.0 without tagging or publishing it.

City remained clean at `df88e87b0f8640607eb55703a283c69da9d904fb`. Keep Close remained at
`5ccd0e97687dd6907a925d7f998c0844c1557a19` with its existing project-file modification. Alphero writing files
were read only. No real app data, private release key, certificate or provider credential was read or changed.

The current native consent flow is manual exchange, not OAuth or personal memory sync. Provider integration,
memory capability verification, consumer adoption and actual app releases are separate work.
