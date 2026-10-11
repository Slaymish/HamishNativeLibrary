// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NativeUpdates", platforms: [.macOS(.v13)],
    products: [.library(name: "NativeUpdates", targets: ["NativeUpdates"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.target(name: "NativeUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")])])
