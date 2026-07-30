import Foundation
import Combine
import Sparkle

/// Sparkle wiring (#46): owns the app's one `SPUStandardUpdaterController`
/// and exposes just what the UI needs — a "check now" action, whether it's
/// currently possible, and the background-check toggle.
///
/// The updater only comes alive when running from an installed .app bundle.
/// An unbundled dev build (`swift build` + run) has no Info.plist, so Sparkle
/// would have no feed URL or public key to work with; demo mode (#39) stays
/// off too, so no update alert can wander into a demo session and Sparkle's
/// bookkeeping never touches defaults during one. When the updater is off,
/// every update surface hides itself via `isAvailable`.
@Observable
final class UpdaterModel {
    private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckCancellable: AnyCancellable?

    /// False while a check or an update install is already in flight —
    /// mirrors Sparkle's `canCheckForUpdates` (KVO) into observation.
    private(set) var canCheckForUpdates = false

    /// Sparkle's own persisted setting, mirrored so SwiftUI can bind to it.
    /// Defaults to on via SUEnableAutomaticChecks in Info.plist (which also
    /// suppresses Sparkle's second-launch permission prompt); the Settings
    /// toggle is the opt-out.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    var isAvailable: Bool { controller != nil }

    init(demo: Bool = DemoMode.isActive) {
        let bundled = Bundle.main.bundlePath.hasSuffix(".app")
        guard bundled, !demo else {
            controller = nil
            automaticallyChecksForUpdates = false
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckCancellable = controller.updater
            .publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    /// The explicit "Check for Updates…" action: shows Sparkle's standard UI,
    /// including the "you're up to date" alert.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
