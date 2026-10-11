# HamishNativeLibrary

Reusable Swift building blocks for personal macOS and iOS apps. Swift 6, macOS 13+, iOS 16+.
The root package has no third-party dependencies. Choose only the products your app needs.

| Product | Provides |
| --- | --- |
| `NativeCore` | App support paths, consistent JSON encoding, private atomic storage, backups and cooperating app/CLI locks |
| `AgentInterchange` | Configurable typed schema, prompts, selective export, validated import, preview/selection, conflicts, provenance, tombstones and checkpoints |
| `NativeUI` | Native sharing consent and prompt/file/paste import review screens |
| `NativeSecurity` | Per-device Keychain storage with explicit failures |
| `NativeUpdates` | Separate macOS-only Sparkle adapter in `Examples/MacUpdater`; no Sparkle dependency in the cross-platform package |

## Start locally

```sh
swift test
swift run exchange-example
scripts/check.sh
scripts/check-platforms.sh # needs Xcode and xcodegen
```

The CLI example uses temporary, fictional reading preferences and makes no network calls.
The native example opens a consent screen, then the prompt/import review flow. Run `xcodegen generate`
from `Examples/NativeDemo` and open the generated project in Xcode.
Choose NativeDemoMac or NativeDemoPhone. Signing is disabled for compilation checks; configure
your own team/signing settings for a device run. The sample permission lasts for the current launch.

## Use in a new app

Add this folder as a local Swift package in Xcode, then add the products above to your app target.
The [private GitHub repository](https://github.com/Slaymish/HamishNativeLibrary) can be added by its URL
once a version is tagged. Authenticate Xcode/Git with an account that has repository access. A consuming manifest can use:

```swift
.package(url: "https://github.com/Slaymish/HamishNativeLibrary.git", .upToNextMinor(from: "0.1.0"))
// target dependencies:
.product(name: "AgentInterchange", package: "HamishNativeLibrary")
.product(name: "NativeUI", package: "HamishNativeLibrary")
```

Use a payload containing ONLY the fields you want exchanged:

```swift
struct Preference: Codable, Equatable, Sendable {
    var topic: String
    var depth: String
}
let config = try ExchangeConfiguration<Preference>(
    appID: "nz.hamish.reading", schemaID: "reading-preference",
    purpose: "Suggest reading preferences from context I choose to share.",
    payloadSchema: .object(properties: [
        "topic": .string(maximum: 120),
        "depth": .string(maximum: 20, choices: ["brief", "detailed"])
    ], required: ["topic", "depth"]))
let url = try AppDirectories.applicationSupport(appID: config.appID)
    .appendingPathComponent("exchange.json")
let session = ExchangeSession(configuration: config, stateURL: url)
```

Import `AgentInterchange` and `NativeCore` for that setup. Show `ExchangeConsentView`, persist its
`ExchangePermission` privately in your app, then show `AgentExchangeView(session:permission:title:)`.
Non-UI clients can use `prompt(permission:)`, `preview(_:permission:)`, and
`apply(_:selecting:permission:)`. Explicit ID-based APIs also support app-controlled manual handovers.

This package implements a manual exchange. It has no provider login, chat scraping, background
sync, inference billing or personal-memory API. Real OAuth is a future provider adapter; the native
consent screen describes the capabilities implemented here. See [provider access](docs/PROVIDERS.md).

## Keep improving it

Use the project [release skill](.agents/skills/release/SKILL.md) for library releases.
Compatible fixes use patch versions; breaking changes before 1.0 use a new minor version.
Apps retain their resolved version until you update their package dependency and rebuild them.
After 1.0, an up-to-next-major range can accept compatible minor/patch releases.
Publishing a library release does not update installed apps by itself. See [adoption and upgrades](docs/ADOPTION.md).

Release tooling follows City's tag-driven approach: changelog → checks → version tag → CI →
release. Consumer apps sign both the archive and feed with their own Sparkle key. Self-signed
or ad-hoc Mac apps remain unnotarised, and iOS distribution needs its own Apple signing route.
See [releasing](docs/RELEASING.md), [security](SECURITY.md), and [source investigation](docs/RESEARCH.md).

Licensed under MIT. Source version: 0.1.0. Check [GitHub releases](https://github.com/Slaymish/HamishNativeLibrary/releases)
for published versions.
