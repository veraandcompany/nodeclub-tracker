import SwiftUI
import TaskbarCore

/// One row in the task list: done-toggle, title, remove.
struct TaskRow: View {
    var task: TaskItem
    var onToggle: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                .lineLimit(1)

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
