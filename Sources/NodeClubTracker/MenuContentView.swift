import AppKit
import SwiftUI
import NodeClubTrackerCore

/// Popover content: pi dashboard + footer.
struct MenuContentView: View {
    var pi: PiDashboardModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                PiDashboardSection(model: pi)
            }
            .frame(maxHeight: maxDashboardHeight)
            Divider()
            footer
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .task { await pi.refresh() }
    }

    /// The `.window`-style MenuBarExtra does not scroll on its own, so cap the
    /// dashboard at ~75% of the menu bar's screen height (measured on the
    /// screen with the pointer) to avoid clipping on short displays.
    private var maxDashboardHeight: CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return max(320, (screen?.visibleFrame.height ?? 800) * 0.75)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("\(AppInfo.name) \(AppInfo.shortVersion) (\(AppInfo.build))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Quit NodeClub Tracker")
            Button {
                SettingsWindowController.show(model: pi)
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings…")
            .accessibilityLabel("Settings")
        }
        .padding([.horizontal, .bottom], 12)
        .padding(.top, 4)
    }
}
