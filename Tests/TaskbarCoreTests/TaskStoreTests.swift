import Foundation
import TaskbarCore
import XCTest

@MainActor
final class TaskStoreTests: XCTestCase {
    /// Isolated defaults suite per call — never touch shared `.standard`.
    private func makeStore() -> TaskStore {
        let suite = "taskbar-tests-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return TaskStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func test_addRejectsBlankTitles() {
        let store = makeStore()
        store.add(title: "   ")
        store.add(title: "\n\t")
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func test_addTrimsTitle() {
        let store = makeStore()
        store.add(title: "  ship it  ")
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks[0].title, "ship it")
    }

    func test_toggleFlipsDoneAndPendingCount() {
        let store = makeStore()
        store.add(title: "a")
        store.add(title: "b")
        XCTAssertEqual(store.pendingCount, 2)
        XCTAssertEqual(store.doneCount, 0)

        store.toggle(id: store.tasks[0].id)
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertEqual(store.doneCount, 1)

        store.toggle(id: store.tasks[0].id)
        XCTAssertEqual(store.pendingCount, 2)
        XCTAssertEqual(store.doneCount, 0)
    }

    func test_toggleUnknownIdIsNoop() {
        let store = makeStore()
        store.add(title: "a")
        store.toggle(id: UUID())
        XCTAssertEqual(store.tasks.count, 1)
    }

    func test_removeDeletesEntry() {
        let store = makeStore()
        store.add(title: "a")
        store.add(title: "b")
        store.remove(id: store.tasks[0].id)
        XCTAssertEqual(store.tasks.map(\.title), ["b"])
    }

    func test_clearDoneOnlyRemovesCompleted() {
        let store = makeStore()
        store.add(title: "a")
        store.add(title: "b")
        store.toggle(id: store.tasks[0].id)
        store.clearDone()
        XCTAssertEqual(store.tasks.map(\.title), ["b"])
    }

    func test_tasksSurviveStoreRelaunch() {
        let suite = "taskbar-tests-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!

        let first = TaskStore(defaults: defaults)
        first.add(title: "persist me")
        first.toggle(id: first.tasks[0].id)

        let second = TaskStore(defaults: defaults)
        XCTAssertEqual(second.tasks.count, 1)
        XCTAssertEqual(second.tasks[0].title, "persist me")
        XCTAssertTrue(second.tasks[0].isDone)
    }
}
