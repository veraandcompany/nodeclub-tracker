import Foundation
import NodeClubTrackerCore
import XCTest

final class PiSessionWatcherTests: XCTestCase {
    /// 2026-09-16T12:00:00Z
    private static let now = Date(timeIntervalSince1970: 1_789_560_000)

    private func makeSessionsDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pi-watcher-\(UUID().uuidString)")
    }

    private func writeSession(
        _ dir: URL,
        project: String,
        file: String,
        mtime: Date,
        content: String? = nil
    ) throws {
        let fileManager = FileManager.default
        let projectDir = dir.appendingPathComponent("--Users-me-\(project)--")
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let header = #"{"type":"session","version":3,"id":"x","timestamp":"2026-09-16T10:00:00.000Z","cwd":"/Users/me/\#(project)"}"#
        let fileURL = projectDir.appendingPathComponent(file)
        try (content ?? header).write(to: fileURL, atomically: true, encoding: .utf8)
        try fileURL.setResourceValues([.contentModificationDate: mtime])
    }

    func test_workingIdleAndStaleClassification() throws {
        let dir = makeSessionsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(dir, project: "active", file: "a.jsonl", mtime: Self.now.addingTimeInterval(-60))
        try writeSession(dir, project: "cooling", file: "b.jsonl", mtime: Self.now.addingTimeInterval(-10 * 60))
        try writeSession(dir, project: "stale", file: "c.jsonl", mtime: Self.now.addingTimeInterval(-2 * 3600))

        let agents = PiSessionWatcher.findAgents(sessionsDir: dir, now: Self.now)
        XCTAssertEqual(agents.count, 2)
        // Most recent first; stale file excluded.
        XCTAssertEqual(agents[0].project, "active")
        XCTAssertEqual(agents[0].status, .working)
        XCTAssertEqual(agents[1].project, "cooling")
        XCTAssertEqual(agents[1].status, .idle)
    }

    func test_multipleSessionsInSameProjectAreSeparateAgents() throws {
        let dir = makeSessionsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(dir, project: "nodebuildai", file: "a.jsonl", mtime: Self.now.addingTimeInterval(-30))
        try writeSession(dir, project: "nodebuildai", file: "b.jsonl", mtime: Self.now.addingTimeInterval(-90))

        let agents = PiSessionWatcher.findAgents(sessionsDir: dir, now: Self.now)
        XCTAssertEqual(agents.count, 2)
        XCTAssertEqual(Set(agents.map(\.project)), Set(["nodebuildai"]))
        XCTAssertEqual(agents.allSatisfy { $0.status == .working }, true)
    }

    func test_missingDirectoryIsEmpty() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("missing-\(UUID().uuidString)")
        XCTAssertTrue(PiSessionWatcher.findAgents(sessionsDir: missing, now: Self.now).isEmpty)
    }

    func test_headerCwdIsPreferredOverDirectoryName() throws {
        let dir = makeSessionsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(dir, project: "realname", file: "a.jsonl", mtime: Self.now.addingTimeInterval(-10))

        let agents = PiSessionWatcher.findAgents(sessionsDir: dir, now: Self.now)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].project, "realname")
    }

    func test_unreadableHeaderFallsBackToDirectoryName() throws {
        let dir = makeSessionsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeSession(
            dir,
            project: "garbage",
            file: "a.jsonl",
            mtime: Self.now.addingTimeInterval(-10),
            content: "not json at all"
        )

        let agents = PiSessionWatcher.findAgents(sessionsDir: dir, now: Self.now)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].project, "--Users-me-garbage--")
    }
}
