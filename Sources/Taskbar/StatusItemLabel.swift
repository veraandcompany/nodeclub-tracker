import SwiftUI
import TaskbarCore

/// What shows in the menu bar itself: icon, live-time, green dot when an agent is working.
struct StatusItemLabel: View {
    var clock: ClockTicker
    var pi: PiDashboardModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
            if pi.workingCount > 0 {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            Text(ClockText.menuBarTime(at: clock.now))
                .monospacedDigit()
        }
    }
}
