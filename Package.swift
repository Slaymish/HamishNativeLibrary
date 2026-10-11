// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HamishNativeLibrary",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "NativeCore", targets: ["NativeCore"]),
        .library(name: "AgentInterchange", targets: ["AgentInterchange"]),
        .library(name: "NativeSecurity", targets: ["NativeSecurity"]),
        .library(name: "NativeUI", targets: ["NativeUI"]),
        .executable(name: "exchange-example", targets: ["ExchangeExample"])
    ],
    targets: [
        .target(name: "NativeCore"),
        .target(name: "AgentInterchange", dependencies: ["NativeCore"]),
        .target(name: "NativeSecurity"),
        .target(name: "NativeUI", dependencies: ["AgentInterchange", "NativeCore"]),
        .executableTarget(name: "ExchangeExample", dependencies: ["AgentInterchange"]),
        .testTarget(name: "NativeCoreTests", dependencies: ["NativeCore"]),
        .testTarget(name: "AgentInterchangeTests", dependencies: ["AgentInterchange"])
    ]
)
