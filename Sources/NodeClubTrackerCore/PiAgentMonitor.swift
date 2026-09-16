import Foundation

/// Live state of pi-agent processes, sourced from the herdr workspace manager.
///
/// `herdr api snapshot` prints a JSON snapshot of every terminal pane it manages,
/// including agent type, working status, and cwd. If herdr is not installed or
/// its server is not running, all probes return empty results — never fatal.
public enum PiAgentMonitor {
    public struct Agent: Identifiable, Sendable, Equatable {
        public enum Status: String, Sendable {
            case working
            case idle
            case unknown
        }

        public var id: String
        public var agent: String
        public var status: Status
        public var cwd: String
        public var label: String?

        public init(id: String, agent: String, status: Status, cwd: String, label: String?) {
            self.id = id
            self.agent = agent
            self.status = status
            self.cwd = cwd
            self.label = label
        }

        public var project: String { (cwd as NSString).lastPathComponent }
    }

    // MARK: - Probing

    /// Candidate locations for the herdr binary (packaged apps have a minimal PATH).
    public static func defaultHerdrCandidates() -> [String] {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["HERDR_BIN"] {
            candidates.append(override)
        }
        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            home + "/.local/bin/herdr",
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
        ])
        return candidates
    }

    /// Resolve an executable herdr binary, or nil when none is found.
    public static func resolveHerdrBin(candidates: [String] = defaultHerdrCandidates()) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Fetch live agents. `herdrBin` overrides resolution (tests/dev).
    public static func fetchAgents(herdrBin: String? = nil) -> [Agent] {
        let bin = herdrBin ?? resolveHerdrBin()
        guard let bin else { return [] }
        guard let data = runHerdr(bin: bin, timeout: 5) else { return [] }
        return parseSnapshot(data: data)
    }

    // MARK: - Pure parsing

    /// Parse a `herdr api snapshot` payload into agents. Malformed payloads → [].
    public static func parseSnapshot(data: Data) -> [Agent] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return [] }
        guard let snapshot = envelope.result?.snapshot else { return [] }
        let labelsByTab = Dictionary(
            uniqueKeysWithValues: (snapshot.tabs ?? [])
                .compactMap { tab -> (String, String)? in
                    guard let id = tab.tabId, let label = tab.label else { return nil }
                    return (id, label)
                }
        )
        return (snapshot.agents ?? []).compactMap { agent -> Agent? in
            guard
                let paneId = agent.paneId,
                let cwd = agent.cwd
            else { return nil }
            let status: Agent.Status
            switch agent.agentStatus {
            case "working": status = .working
            case "idle": status = .idle
            default: status = .unknown
            }
            let label = agent.tabId.flatMap { labelsByTab[$0] }
            return Agent(
                id: paneId,
                agent: agent.agent ?? "unknown",
                status: status,
                cwd: cwd,
                label: label
            )
        }
    }

    // MARK: - Subprocess

    /// Run `herdr api snapshot`, bounded by `timeout` seconds.
    /// Must be called off the main actor (blocks briefly).
    private static func runHerdr(bin: String, timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["api", "snapshot"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Box + semaphore: the read runs on a private queue; the wait below is the
        // only cross-thread handoff, so the box is safely published after signal.
        final class DataBox: @unchecked Sendable { var data: Data? }
        let box = DataBox()
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "nodeclubtracker.herdr-stdout")
        queue.async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            semaphore.signal()
        }
        let completed = semaphore.wait(timeout: .now() + timeout) == .success
        if !completed {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, let data = box.data, !data.isEmpty else { return nil }
        return data
    }

    // MARK: - Wire format (subset of herdr's session snapshot)

    private struct Envelope: Decodable {
        let result: Result?

        struct Result: Decodable {
            let snapshot: Snapshot?

            struct Snapshot: Decodable {
                let agents: [AgentEntry]?
                let tabs: [Tab]?

                struct AgentEntry: Decodable {
                    let agent: String?
                    let agentStatus: String?
                    let cwd: String?
                    let paneId: String?
                    let tabId: String?
                }

                struct Tab: Decodable {
                    let tabId: String?
                    let label: String?
                }
            }
        }
    }
}
