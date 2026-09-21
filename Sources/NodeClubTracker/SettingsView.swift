import SwiftUI
import NodeClubTrackerCore

/// Compact settings content: General + About in a single grouped Form.
///
/// The three Form modifiers are load-bearing for the native settings look:
/// `.formStyle(.grouped)` for inset rounded sections,
/// `.scrollContentBackground(.hidden)` so the window chrome shows through,
/// and top content margins for breathing room under the title bar.
struct SettingsView: View {
    var model: PiDashboardModel

    /// Dashboard auto-refresh cadence in seconds; persisted via UserDefaults.
    @AppStorage(AppSettings.refreshIntervalKey)
    private var refreshInterval = AppSettings.defaultRefreshInterval

    /// Verbose logging toggle; persisted via UserDefaults.
    @AppStorage(VerboseLogger.verboseLoggingKey)
    private var verboseLogging = false

    var body: some View {
        Form {
            Section {
                Picker("Refresh", selection: $refreshInterval) {
                    ForEach(AppSettings.refreshIntervals, id: \.self) { seconds in
                        Text(AppSettings.refreshLabel(seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Verbose logging", isOn: $verboseLogging)
            } header: {
                Text("General")
            } footer: {
                Text("How often the dashboard rescans pi sessions and OpenCode data. Verbose logging appends detailed refresh lines to the log file below, so the last lines show what the app was doing when it crashed. Crash backtraces are written to the log even when the toggle is off.")
            }

            Section("About") {
                LabeledContent("Version", value: "\(AppInfo.shortVersion) (\(AppInfo.build))")
                LabeledContent("Pi sessions") {
                    pathLabel(PiSessionReader.defaultSessionsDir)
                }
                LabeledContent("OpenCode data") {
                    pathLabel(OpencodeSessionReader.defaultDataDir)
                }
                LabeledContent("Usage history") {
                    pathLabel(PiHistoryStore.defaultFileURL)
                }
                LabeledContent("Log file") {
                    pathLabel(VerboseLogger.logFileURL)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .frame(minWidth: 420, minHeight: 340)
        .onChange(of: refreshInterval) { _, newValue in
            applyRefreshInterval(newValue)
        }
        .onChange(of: verboseLogging) { _, newValue in
            if newValue {
                VerboseLogger.logEnabledMarker()
            } else {
                VerboseLogger.logDisabledMarker()
            }
        }
    }

    private func pathLabel(_ url: URL) -> some View {
        Text((url.path as NSString).abbreviatingWithTildeInPath)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func applyRefreshInterval(_ seconds: Double) {
        model.stopAutoRefresh()
        model.startAutoRefresh(interval: .seconds(seconds))
    }
}
