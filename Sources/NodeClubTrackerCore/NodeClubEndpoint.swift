import Foundation

/// The NodeClub inference endpoint — the single source of truth for what counts
/// as NodeClub traffic across all data sources.
///
/// pi and OpenCode attribute turns by provider id (`nodeclub`, the provider whose
/// baseUrl is this endpoint); Hermes has no such id and records the endpoint
/// itself on every usage row, so it is matched on this host.
public enum NodeClubEndpoint {
    public static let host = "api.nodeclub.ai"
    public static let baseUrl = "https://" + host + "/v1"

    /// Whether a recorded endpoint URL routes to NodeClub.
    /// Host-only on purpose: any scheme/path/port on `api.nodeclub.ai` counts,
    /// and a future `/v2` path change won't silently stop tracking.
    public static func isNodeClub(_ urlString: String?) -> Bool {
        guard
            let urlString,
            let url = URL(string: urlString),
            let urlHost = url.host
        else { return false }
        return urlHost.lowercased() == host
    }
}
