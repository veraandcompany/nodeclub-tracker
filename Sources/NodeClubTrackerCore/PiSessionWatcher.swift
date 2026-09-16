import Foundation

/// A pi agent, identified by its session file and liveness (mtime activity).
public struct PiAgent: Identifiable, Sendable, Equatable {
    public enum Status: Sendable {
        case working
        case idle
    }

    public var id: String
    public var project: String
    public var status: Status
    public var lastActivity: Date

    public init(id: String, project: String, status: Status, lastActivity: Date) {
        self.id = id
        self.project = project
        self.status = status
        self.lastActivity = lastActivity
    }
}

/// Detects running pi agents from session-file activity — works for pi inside
/// herdr, in a bare terminal, or anywhere sessions are persisted.
///
/// Signal: pi appends to its session JSONL as it works, so a file touched
/// recently means that agent is live. No subprocesses, no external services.
/// Known limitation: during one very long tool call (no writes) a working
/// agent can briefly read as idle until the next append.
public enum PiSessionWatcher {
    /// mtime within this window → working (seconds).
    public static let defaultWorkingWindow: TimeInterval = 120
    /// mtime within this window → idle; older files are not listed (seconds).
    public static let defaultRecentWindow: TimeInterval = 30 * 60

    /// Find agents with recent session activity, most recent first.
    public static func findAgents(
        sessionsDir: URL,
        now: Date = Date(),
        workingWindow: TimeInterval = defaultWorkingWindow,
        recentWindow: TimeInterval = defaultRecentWindow
    ) -> [PiAgent] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return [] }

        var agents: [PiAgent] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard
                let values = try? url.resourceValues(forKeys: keys),
                let mtime = values.contentModificationDate
            else { continue }
            let age = now.timeIntervalSince(mtime)
            let status: PiAgent.Status
            if age <= workingWindow {
                status = .working
            } else if age <= recentWindow {
                status = .idle
            } else {
                continue
            }
            agents.append(PiAgent(
                id: url.lastPathComponent,
                project: project(for: url),
                status: status,
                lastActivity: mtime
            ))
        }
        return agents.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Project name

    /// Exact project name from the session header's `cwd` (first line only).
    /// Falls back to the (lossy) encoded directory name when unreadable.
    private static func project(for sessionFile: URL) -> String {
        if let cwd = headerCwd(of: sessionFile) {
            return (cwd as NSString).lastPathComponent
        }
        return sessionFile.deletingLastPathComponent().lastPathComponent
    }

    private static func headerCwd(of sessionFile: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: sessionFile) else { return nil }
        defer { try? handle.close() }
        guard
            let chunk = try? handle.read(upToCount: 4096),
            let firstLine = String(decoding: chunk, as: UTF8.self)
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first,
            let bytes = firstLine.data(using: .utf8),
            let header = try? JSONDecoder().decode(Header.self, from: bytes),
            let cwd = header.cwd
        else { return nil }
        return cwd
    }

    private struct Header: Decodable {
        let cwd: String?
    }
}
