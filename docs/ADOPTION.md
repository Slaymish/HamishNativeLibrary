# Adoption and updates across apps

The root package is the shared code source. Consumer applications choose products and versions. It is
not a runtime plug-in that can replace code inside already installed applications.

During development, a local path dependency makes library source edits available at the app's next build.
Use that temporarily when checking a fix against City or Keep Close, then pin a released version before
finishing integration. Both repositories now use the library's shared primitives; their domain rules,
saved formats, existing working state and behavior remain under their own guidance.

Once hosted on GitHub, version tags become Swift Package Manager versions. Before 1.0 use an
up-to-next-minor range for compatible patch fixes, or an exact pin when an app needs a frozen release.
Use a new minor for breaking changes before 1.0. After 1.0 follow SemVer major/minor/patch rules and use
up-to-next-major for compatible updates. SwiftPM still respects `Package.resolved`; publishing does not
silently change every app's checkout.

For each improvement:

1. Fix and test the library. Add regression coverage when there is an actual behavioral failure.
2. Document public API/schema changes. Never change a deployed import schema without a version/migration.
3. Use the release skill to prepare a reviewed tag/release.
4. In each consuming app, update the package in Xcode or `swift package update HamishNativeLibrary` for a
   SwiftPM consumer. Inspect/commit its resolution change and run that app's own platform checks.
5. Rebuild and release each app. macOS installed users receive the compiled improvement through that
   app's Sparkle update; iOS users through that app's configured Apple distribution channel.

`Examples/MacUpdater` is a separate subpackage, available at the subdirectory when using a local checkout.
Xcode remote package URLs resolve the repository root, not arbitrary subfolders. For a remote consuming
macOS app, add Sparkle 2.10.0 directly and copy the small adapter into the app, or later promote NativeUpdates
to its own repository. This deliberately avoids pulling a macOS binary artifact into every iOS dependency.

Keep Close uses strict schema decoding for its existing version-1/2 envelope, shared file/JSON/lock helpers,
snapshot comparison, native transfer helpers and authentication gate. City uses shared file/JSON/clipboard
helpers and per-device Keychain storage, retaining its original pairing accessibility and key identifiers.
Keep Close's additive domain merges and City's agent runtime/RealityKit code stay in their repositories.
NativeCore is suitable for simple local JSON state, not a replacement for a ledger,
distributed database or filesystem coordination over cloud storage.

Release script entrypoints can delegate to scripts in the resolved library checkout, so they share its
version. Keep Close's archive/appcast wrappers do this. Its self-signed path signs both archive and feed
using the existing app-specific Sparkle key. App updater objects remain macOS app adapters: the root package
does not import Sparkle, and the optional NativeUpdates subpackage is not remotely addressable by Xcode.

Version 0.3 adds NativeSync for Keep Close's two-way portable records and City's durable Mac mirror.
Consumers add the NativeSync product, Bonjour usage declarations and repository/lifecycle adapters.
Read [local sync](LOCAL_SYNC.md) before adapting another store; per-device security and runtime authority
are excluded deliberately. Pairing and phone validation are app setup, not automatic library installation.
