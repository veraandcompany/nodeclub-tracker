import SwiftUI
import NodeClubTrackerCore

/// Popover content: pi dashboard + footer.
struct MenuContentView: View {
    var pi: PiDashboardModel

    var body: some View {
        VStack(spacing: 0) {
            PiDashboardSection(model: pi)
            Divider()
            footer
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .task { await pi.refresh() }
    }

    private var footer: some View {
        Text("\(AppInfo.name) \(AppInfo.shortVersion) (\(AppInfo.build))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .bottom], 12)
            .padding(.top, 4)
    }
}
