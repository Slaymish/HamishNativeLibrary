import Foundation
import Combine
import Sparkle

/// Add this separate package to a macOS app only. Retain one instance for the app's lifetime.
@MainActor public final class AppUpdater: ObservableObject {
    @Published public private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController
    public init(enabled: Bool = true) {
        #if DEBUG
        let start = false
        #else
        let start = enabled
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    public func checkForUpdates() { controller.checkForUpdates(nil) }
}
