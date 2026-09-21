import AppKit

/// Toggles Dock presence for this menu-bar-only app.
///
/// The app runs as `.accessory` (no Dock icon, no Cmd-Tab). A settings window
/// needs the app to be a regular, activatable app in order to take focus, so
/// we reference-count `.regular` while a window is open and drop back to
/// `.accessory` when the last window closes.
@MainActor
enum AppActivationPolicy {
    private static var count = 0

    static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
