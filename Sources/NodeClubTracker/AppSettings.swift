import Foundation

/// Persisted app settings (UserDefaults), shared between the app entry point
/// and the settings window.
enum AppSettings {
    static let refreshIntervalKey = "refreshInterval"
    static let defaultRefreshInterval: Double = 20

    /// Picker options for the refresh interval, in seconds.
    static let refreshIntervals: [Double] = [10, 20, 30, 60, 120]

    static func refreshLabel(_ seconds: Double) -> String {
        switch Int(seconds) {
        case 60: return "Every minute"
        case 120: return "Every 2 minutes"
        default: return "Every \(Int(seconds)) seconds"
        }
    }

    /// Current refresh interval in seconds; falls back to the default when unset.
    static var refreshInterval: Double {
        let stored = UserDefaults.standard.double(forKey: refreshIntervalKey)
        return stored > 0 ? stored : defaultRefreshInterval
    }
}
