import SwiftUI
import UIKit

/// Picks a task status explicitly instead of cycling through them on tap.
struct TaskStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: WorkTask
    let onPick: (TaskStatus) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.inkSecondary)
                    .lineLimit(2)

                VStack(spacing: 8) {
                    ForEach(TaskStatus.allCases) { status in
                        statusRow(status)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AppTheme.spaceLG)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardBackground())
            .navigationTitle("สถานะงาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
        }
    }

    private func statusRow(_ status: TaskStatus) -> some View {
        let isCurrent = status == task.status
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(status)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: status.systemImage)
                    .font(.title2)
                    .foregroundStyle(status.color)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(status.color.opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.label)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(status.color)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .fill(isCurrent ? status.color.opacity(0.1) : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .strokeBorder(isCurrent ? status.color.opacity(0.45) : AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.label) \(status.detail)")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
