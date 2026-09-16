import SwiftUI
import TaskbarCore

/// Popover content: pi dashboard + footer.
struct MenuContentView: View {
    var clock: ClockTicker
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
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(ClockText.popoverTime(at: clock.now))
                    .font(.caption)
                    .monospacedDigit()
                Text("\(AppInfo.name) \(AppInfo.shortVersion) (\(AppInfo.build))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
                .font(.caption)
        }
        .padding([.horizontal, .bottom], 12)
        .padding(.top, 4)
    }
}
