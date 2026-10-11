// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LocalSyncSmoke", platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "SyncSmoke", dependencies: [.product(name: "NativeSync", package: "HamishNativeLibrary")])])
