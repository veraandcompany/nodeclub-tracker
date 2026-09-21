import SwiftUI
import NodeClubTrackerCore

@main
struct NodeClubTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(pi: appDelegate.dashboard)
        } label: {
            StatusItemLabel(pi: appDelegate.dashboard)
        }
        .menuBarExtraStyle(.window)
    }
}
