import AppKit
import NodeClubTrackerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owns the dashboard model so auto-refresh can be started from
    /// `applicationDidFinishLaunching`. A background `Task` created in
    /// `App.init()` runs before the main run loop is up and is never
    /// scheduled, which silently kills the auto-refresh loop.
    let dashboard: PiDashboardModel

    override init() {
        dashboard = PiDashboardModel(log: { line in
            VerboseLogger.log(line)
        })
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no application menu bar.
        NSApp.setActivationPolicy(.accessory)
        // Capture fatal signals + uncaught exceptions to the log file.
        VerboseLogger.installCrashHandlers()
        VerboseLogger.log("launch: version \(AppInfo.shortVersion) build \(AppInfo.build), pid \(ProcessInfo.processInfo.processIdentifier)")
        dashboard.startAutoRefresh(interval: .seconds(AppSettings.refreshInterval))
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Distinguishes clean shutdowns from external kills: no shutdown line
        // before a disappearance means the process was terminated from outside.
        VerboseLogger.log("shutdown: clean termination, pid \(ProcessInfo.processInfo.processIdentifier)")
    }
}
