# Releases

City is the primary reference: prepare accurate notes, verify code, tag the checked commit, watch CI and
verify the actual release/feed. Credential setup is separate. This checkout contains no private keys and
never installs certificates or changes Keychain trust.

## Library releases

The library is source distributed through Git and Swift Package Manager. It does not need Sparkle,
Apple code signing or notarisation. Version tags select source; consumer apps compile it into their builds.

1. Choose a version according to `docs/ADOPTION.md`, update `VERSION`, and add a dated changelog section.
2. Run `scripts/check.sh`, `scripts/check-platforms.sh` and the separate MacUpdater build.
3. Review/commit only the library changes. Create an annotated `vMAJOR.MINOR.PATCH` tag after remote
   main is clean and green. Do not replace a released tag.
4. The `Library release` workflow reruns CI, validates tag/version/notes and creates a GitHub draft.
5. Review/publish the draft, then update consumer apps' dependencies, tests and app releases.

No GitHub repository, push, remote tag or release is created by local setup. Suggested repo name:
`Slaymish/HamishNativeLibrary`. When authorised, create it with the chosen visibility, set `origin`, push
main, verify CI, and release 0.1.0. Authenticate gh commands as Slaymish per command, without switching
the machine's default work account. Use the [release skill](../.agents/skills/release/SKILL.md).

## Consumer macOS apps

Add Sparkle 2.10.0 to the Mac app target only. The `NativeUpdates` adapter is in the separate example
subpackage. Retain the updater and wire `checkForUpdates()` to a menu button, disabled when `canCheck`
is false. Debug builds do not start automatic checks.

In your app's Info.plist, configure:

```xml
<key>SUFeedURL</key><string>https://github.com/OWNER/REPO/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>YOUR_APP_SPECIFIC_BASE64_PUBLIC_KEY</string>
<key>SURequireSignedFeed</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
```

Also supply `LSMinimumSystemVersion`, semantic `CFBundleShortVersionString` and an increasing positive
integer `CFBundleVersion`. Keep the Sparkle package and release tools at the same version. Embed & Sign
the framework and follow the app's platform entitlements. Sandbox integration needs the upstream guide.
Do not disable sandbox/hardened-runtime or library validation just to make an incompatible build work.

Sparkle Ed25519 signatures authenticate updates against the public key installed in the app. They are
separate from Apple code signatures and notarisation. Keep an app-specific key, secure recovery copy,
and stable embedded public key. Do not silently rotate it. Signing both archive and feed protects both
downloaded code and update metadata. [Sparkle signing guidance](https://sparkle-project.org/documentation/).

The release scripts use existing keys and refuse missing inputs. For a fresh app, a maintainer must
deliberately generate its update keys and arrange secure local/CI storage before the first release. This
setup does not generate/import actual app credentials, copy City's or Keep Close's private key, or add secrets.

Build with an existing signing identity, or explicitly select ad-hoc (`-`) for a personal build:

```sh
MACOS_SIGNING_IDENTITY='-' scripts/build-macos.sh App.xcodeproj App 0.1.0 1 work/App.xcarchive
SPARKLE_BIN=/path/to/Sparkle/bin SPARKLE_KEY_FILE=/secure/path/app-update.key \
  scripts/package-macos.sh work/App.xcarchive/Products/Applications/App.app \
  OWNER/REPO 0.1.0 dist/0.1.0 self-signed
```

The app project owns nested signing and entitlements. The packaging script verifies all code signatures,
checks feed configuration/version/public key, creates a symlink-preserving ZIP, signs it, independently
verifies its signature against the embedded public key, writes/signs/verifies the feed and records hashes.
It stages outputs before moving them to a new directory and refuses an existing destination.

Outputs are `App-vVERSION.zip`, `appcast.xml`, `SHA256SUMS`. Publish all together, with the feed pointing
at the version's immutable asset URL. No deltas, embedded release-note files or DMG are generated here.
The one-item feed advertises the latest full update. Verify the new build is greater than every published
build; the local script cannot know remote release history. GitHub latest-download URLs must be accessible
to installed clients; a private repo needs an authenticated update host rather than this public-feed scheme.

`Examples/macos-release.yml` is a consuming-repo template. Copy the four build/packaging helpers into
that app and the workflow into `.github/workflows/`, set its documented project variables and app-specific
Sparkle secret. It is tag driven like City, builds an ad-hoc archive with the app's own configuration and
creates a draft with signed ZIP/feed. Add that app's tests as a required predecessor. If the app project
is generated, add its existing generator step before building. Do not apply it blindly to existing apps.

## Distribution constraints and validation

A self-signed certificate or an ad-hoc signature does not make an app Apple-trusted. These builds are not
notarised and first launch may need explicit user approval through macOS Privacy & Security. Never present
an Ed25519 signature as Apple endorsement or remove OS protections to bypass an install failure.
Developer ID/notarisation requires the relevant Apple Developer Program credentials.
[Apple Developer ID](https://developer.apple.com/developer-id/).

The optional `notarized` packaging mode requires a Developer ID app, a valid stapled ticket and a passing
Gatekeeper assessment. It does not submit anything to Apple. Use Apple's archive/export/notarytool path
once credentials exist; build and sign every nested executable appropriately, notarise and staple before
creating the final Sparkle archive. [Apple notarisation requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Sparkle is macOS only. An Apple Account can support limited personal device testing through Xcode; App
Store/TestFlight and broader iOS distribution need their own membership/provisioning route. This library
does not turn a GitHub ZIP into an installable iPhone release. [Apple account capabilities](https://developer.apple.com/help/account/basics/about-your-developer-account).

Before publishing an app feed, test from the previous installed build on a separate data directory/device:
startup, loading Sparkle, scheduled/manual checks, archive validation, replacement/relaunch, preservation of
data, permissions and Keychain access. Test first launch on another Mac, correct architecture and minimum
OS, plus rejection of a tampered archive/feed. A script signing successfully is not proof of that installed
update experience. Drafts are not live feeds; publication must expose all assets together. Never overwrite
a published asset/tag or silently switch update keys; fix forward with a new version.
