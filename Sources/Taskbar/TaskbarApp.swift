import SwiftUI
import TaskbarCore

@main
struct TaskbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var clock = ClockTicker()
    @State private var pi = PiDashboardModel()

    init() {
        // Label needs a live tick even while the popover is closed.
        clock.start()
        pi.startAutoRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(clock: clock, pi: pi)
        } label: {
            StatusItemLabel(clock: clock, pi: pi)
        }
        .menuBarExtraStyle(.window)
    }
}
