import AppKit
import NodeClubTrackerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no application menu bar.
        NSApp.setActivationPolicy(.accessory)
        // Capture fatal signals + uncaught exceptions to the log file.
        VerboseLogger.installCrashHandlers()
        VerboseLogger.log("launch: version \(AppInfo.shortVersion) build \(AppInfo.build), pid \(ProcessInfo.processInfo.processIdentifier)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Distinguishes clean shutdowns from external kills: no shutdown line
        // before a disappearance means the process was terminated from outside.
        VerboseLogger.log("shutdown: clean termination, pid \(ProcessInfo.processInfo.processIdentifier)")
    }
}
