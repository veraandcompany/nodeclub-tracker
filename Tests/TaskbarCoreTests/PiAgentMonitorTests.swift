import Foundation
import TaskbarCore
import XCTest

final class PiAgentMonitorTests: XCTestCase {
    private static let snapshotJSON = """
    {"id":"cli:api:snapshot","result":{"snapshot":{"agents":[
        {"agent":"pi","agent_status":"working","cwd":"/Users/me/projects/nodebuildai","pane_id":"w1:p1","tab_id":"w1:t1"},
        {"agent":"pi","agent_status":"idle","cwd":"/Users/me/projects/elbudosabio","pane_id":"w1:p2","tab_id":"w1:t2"},
        {"agent":"codex","agent_status":"working","cwd":"/Users/me/projects/other","pane_id":"w1:p3","tab_id":"w1:t3"}
    ],"tabs":[
        {"tab_id":"w1:t1","label":"nodebuildai"},
        {"tab_id":"w1:t2","label":"Hermes"}
    ]},"type":"session_snapshot"}}
    """

    func test_parseSnapshotMapsAgentsAndLabels() {
        let agents = PiAgentMonitor.parseSnapshot(data: Data(Self.snapshotJSON.utf8))
        XCTAssertEqual(agents.count, 3)
        XCTAssertEqual(agents[0].id, "w1:p1")
        XCTAssertEqual(agents[0].agent, "pi")
        XCTAssertEqual(agents[0].status, .working)
        XCTAssertEqual(agents[0].project, "nodebuildai")
        XCTAssertEqual(agents[0].label, "nodebuildai")
        XCTAssertEqual(agents[1].status, .idle)
        XCTAssertEqual(agents[1].label, "Hermes")
        XCTAssertNil(agents[2].label)
        XCTAssertEqual(agents[2].agent, "codex")
    }

    func test_parseSnapshotIgnoresAgentsWithoutIdentity() {
        let json = #"{"result":{"snapshot":{"agents":[{"agent":"pi","agent_status":"working"}]}}}"#
        let agents = PiAgentMonitor.parseSnapshot(data: Data(json.utf8))
        XCTAssertTrue(agents.isEmpty)
    }

    func test_parseSnapshotMalformedDataIsEmpty() {
        XCTAssertTrue(PiAgentMonitor.parseSnapshot(data: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(PiAgentMonitor.parseSnapshot(data: Data()).isEmpty)
    }

    func test_fetchAgentsWithMissingBinaryIsEmpty() {
        let agents = PiAgentMonitor.fetchAgents(herdrBin: "/nonexistent/herdr-\(UUID().uuidString)")
        XCTAssertTrue(agents.isEmpty)
    }

    func test_unknownStatusFallsBackToUnknown() {
        let json = #"{"result":{"snapshot":{"agents":[{"agent":"pi","agent_status":"paused","cwd":"/x","pane_id":"p"}]}}}"#
        let agents = PiAgentMonitor.parseSnapshot(data: Data(json.utf8))
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].status, .unknown)
    }
}
