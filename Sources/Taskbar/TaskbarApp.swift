import SwiftUI
import TaskbarCore

@main
struct TaskbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var pi = PiDashboardModel()

    init() {
        pi.startAutoRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(pi: pi)
        } label: {
            StatusItemLabel(pi: pi)
        }
        .menuBarExtraStyle(.window)
    }
}
