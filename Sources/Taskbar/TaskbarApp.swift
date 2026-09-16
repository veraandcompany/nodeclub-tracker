import SwiftUI
import TaskbarCore

@main
struct TaskbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var clock = ClockTicker()
    @State private var tasks = TaskStore()

    init() {
        // Label needs a live tick even while the popover is closed.
        clock.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(clock: clock, tasks: tasks)
        } label: {
            StatusItemLabel(clock: clock)
        }
        .menuBarExtraStyle(.window)
    }
}
