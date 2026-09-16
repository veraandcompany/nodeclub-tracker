import SwiftUI
import TaskbarCore

/// What shows in the menu bar itself: icon + live time.
struct StatusItemLabel: View {
    var clock: ClockTicker

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")
            Text(ClockText.menuBarTime(at: clock.now))
                .monospacedDigit()
        }
    }
}
