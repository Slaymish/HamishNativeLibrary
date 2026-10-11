# Adoption and updates across apps

The root package is the shared code source. Consumer applications choose products and versions. It is
not a runtime plug-in that can replace code inside already installed applications.

During development, a local path dependency makes library source edits available at the app's next build.
Use that in a temporary branch when checking a fix against City or Keep Close. Neither repository was
migrated in this setup; their existing working state and behavior remain under their own guidance.

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

Practical first adoption: use the new exchange layer in a small fictional-context app. Keep Close's additive
domain merges and City's agent runtime/RealityKit code should stay in their repositories until separately
integrated and tested. NativeCore is suitable for simple local JSON state, not a replacement for a ledger,
distributed database or filesystem coordination over cloud storage.
