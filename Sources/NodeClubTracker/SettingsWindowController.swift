import AppKit
import SwiftUI
import NodeClubTrackerCore

/// Small settings window for the menu bar app.
///
/// Deliberately an `NSWindowController` instead of a SwiftUI `Window` scene:
/// a `Window` scene can't be sized/positioned at creation and would need
/// extra scene plumbing, while the controller gives us frame autosave
/// (the window opens centered once, then remembers wherever the user
/// drags it afterwards — the native answer to "always in the same spot"),
/// a minimum size, and a clean close lifecycle.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    /// Show the settings window, creating it on first use.
    static func show(model: PiDashboardModel) {
        if let shared {
            shared.showWindow(nil)
            return
        }
        let controller = SettingsWindowController(model: model)
        shared = controller
        controller.showWindow(nil)
    }

    private init(model: PiDashboardModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow(model: model)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow(model: PiDashboardModel) {
        guard let window else { return }
        window.title = "Settings"
        window.minSize = NSSize(width: 420, height: 340)
        window.isMovableByWindowBackground = true
        window.center()
        // Restores the last saved frame (and overrides the centering) if one exists.
        window.setFrameAutosaveName("SettingsWindow")
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppActivationPolicy.enter()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
