import SwiftUI
import TaskbarCore

/// Popover content: clock header, task list, add field, footer.
struct MenuContentView: View {
    var clock: ClockTicker
    @Bindable var tasks: TaskStore
    @State private var draftTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            taskList
            Divider()
            addField
            Divider()
            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 2) {
            Text(ClockText.popoverTime(at: clock.now))
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(ClockText.longDate(at: clock.now))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            listHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    if tasks.tasks.isEmpty {
                        Text("No tasks yet")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(tasks.tasks) { task in
                            TaskRow(
                                task: task,
                                onToggle: { tasks.toggle(id: task.id) },
                                onRemove: { tasks.remove(id: task.id) }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private var listHeader: some View {
        HStack {
            Text("Tasks")
                .font(.headline)
            Text("\(tasks.pendingCount) open")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if tasks.doneCount > 0 {
                Button("Clear completed") { tasks.clearDone() }
                    .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            TextField("Add a task…", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addDraft)
            Button("Add", action: addDraft)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Text("\(AppInfo.name) \(AppInfo.shortVersion) (\(AppInfo.build))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
                .font(.caption)
        }
        .padding([.horizontal, .bottom], 12)
        .padding(.top, 4)
    }

    private func addDraft() {
        tasks.add(title: draftTitle)
        draftTitle = ""
    }
}
