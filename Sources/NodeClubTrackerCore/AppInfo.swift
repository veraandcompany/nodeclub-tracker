import Foundation

/// Build metadata surfaced in the popover footer.
public enum AppInfo {
    public static let name = "NodeClub Tracker"

    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}
