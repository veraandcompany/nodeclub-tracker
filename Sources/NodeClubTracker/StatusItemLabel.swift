import SwiftUI
import NodeClubTrackerCore

/// What shows in the menu bar itself: icon, with a green dot while an agent is working.
struct StatusItemLabel: View {
    var pi: PiDashboardModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
            if pi.workingCount > 0 {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
    }
}
