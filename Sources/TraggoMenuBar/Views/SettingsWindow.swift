import SwiftUI
import AppKit

/// Owns the settings window and reuses a single instance. Modelled on
/// Rectangle's preferences window: a toolbar-style `NSTabViewController` with an
/// icon per section, each section a SwiftUI view hosted in an `NSHostingController`.
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var windowController: NSWindowController?

    private init() {}

    func show(model: AppModel) {
        if windowController == nil {
            windowController = Self.makeWindowController(model: model)
        }
        // An .accessory app isn't active when the menu is clicked, so activate
        // and order front or the window opens behind the focused app.
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    private static func makeWindowController(model: AppModel) -> NSWindowController {
        let tabController = NSTabViewController()
        tabController.tabStyle = .toolbar

        tabController.addTabViewItem(item("Connection", symbol: "person.crop.circle",
                                          content: ConnectionSettingsView(), model: model))
        tabController.addTabViewItem(item("Tag Sets", symbol: "tag",
                                          content: TagSetsSettingsView(), model: model))
        tabController.addTabViewItem(item("History", symbol: "clock.arrow.circlepath",
                                          content: HistorySettingsView(), model: model))

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference          // centred, System-Settings layout
        window.titlebarSeparatorStyle = .none       // no line under the toolbar
        window.isReleasedWhenClosed = false         // we reuse the controller
        window.center()

        return NSWindowController(window: window)
    }

    private static func item(_ label: String, symbol: String,
                             content: some View, model: AppModel) -> NSTabViewItem {
        // Fixed frame so every section is the same size and the window doesn't
        // resize as you switch tabs.
        let host = NSHostingController(rootView:
            AnyView(content.environment(model).frame(width: 500, height: 420)))
        // In `.toolbar` style the window title follows the selected controller's
        // `title`. Give every section the same title so it stays static (an
        // unset title would show "Untitled" when switching tabs).
        host.title = "Traggo Menu App Settings"
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
