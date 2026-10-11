# HamishNativeLibrary

Swift 6 package for macOS/iOS. Root products are dependency-free. Sparkle stays in the separate macOS
example; do not add its binary artifact to the root package or iOS targets.

Use `scripts/check.sh` for unit/example/script checks, `scripts/check-platforms.sh` for both native
builds (Xcode + xcodegen), and `swift build --package-path Examples/MacUpdater` for the updater adapter.
Generated native Xcode project/build outputs are ignored. No paid model calls are needed for these checks.

Read docs/INTERCHANGE.md before changing the contract or merge/checkpoint behavior. Preserve unknown-key
rejection, user-confirmed conflicts, tombstones, selected export scope, preview freshness, receipt binding,
default uncertainty and transaction boundaries. Tests/fixtures contain fictional context only. Never
represent manual handover or inference access as verified agent-memory sync.

For releases use [.agents/skills/release/SKILL.md](.agents/skills/release/SKILL.md). City is the preferred
release reference; Keep Close supplies interchange ideas. Read docs/RESEARCH.md for the inspected sources.
Preserve user work in consumers and do not migrate their data, dependencies or signing keys as library work.

Keep API changes compatible or release an appropriate version. Installed apps require a dependency update,
rebuild and app release to receive shared fixes; see docs/ADOPTION.md. Use Slaymish credentials per gh command,
without changing the default work account. No credential creation, Keychain trust changes or notarisation
submission belongs in ordinary release preparation.
