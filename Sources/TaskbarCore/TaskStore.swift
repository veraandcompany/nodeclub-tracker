import Foundation
import Observation

/// Observable, persisted task list backing the popover.
///
/// Backed by `UserDefaults` (JSON blobs) so tasks survive relaunches.
/// Tests inject a suite-named `UserDefaults` for isolation.
@MainActor
@Observable
public final class TaskStore {
    public static let defaultStorageKey = "taskbar.tasks.v1"

    public private(set) var tasks: [TaskItem] = []

    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = TaskStore.defaultStorageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    public var pendingCount: Int { tasks.count { !$0.isDone } }
    public var doneCount: Int { tasks.count { $0.isDone } }

    public func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TaskItem(title: trimmed))
        persist()
    }

    public func toggle(id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone.toggle()
        persist()
    }

    public func remove(id: TaskItem.ID) {
        tasks.removeAll { $0.id == id }
        persist()
    }

    public func clearDone() {
        tasks.removeAll { $0.isDone }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([TaskItem].self, from: data)
        else { return }
        tasks = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
