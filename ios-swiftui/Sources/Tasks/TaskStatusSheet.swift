import SwiftUI
import UIKit

/// Picks a task status explicitly instead of cycling through them on tap.
struct TaskStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: WorkTask
    let onPick: (TaskStatus) -> Void

    @State private var appeared = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                HStack(spacing: 12) {
                    Image(systemName: task.status.systemImage)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(task.status.color)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(task.status.color.opacity(0.14))
                                .overlay(Circle().strokeBorder(task.status.color.opacity(0.25), lineWidth: 1))
                        )
                        .symbolEffect(.bounce, value: task.status)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("เลือกสถานะใหม่")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.inkMuted)
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                        .fill(.ultraThinMaterial)
                )

                VStack(spacing: 8) {
                    ForEach(Array(TaskStatus.allCases.enumerated()), id: \.element.id) { index, status in
                        statusRow(status)
                            .tasksStaggeredAppear(index: index, baseDelay: 0.08)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
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
            .onAppear {
                guard !reduceMotion else {
                    appeared = true
                    return
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    appeared = true
                }
            }
        }
    }

    private func statusRow(_ status: TaskStatus) -> some View {
        let isCurrent = status == task.status
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                onPick(status)
            }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: status.systemImage)
                    .font(.title2)
                    .foregroundStyle(status.color)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [status.color.opacity(0.22), status.color.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(status.color)
                        .symbolEffect(.bounce, value: isCurrent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .fill(isCurrent ? status.color.opacity(0.12) : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .strokeBorder(isCurrent ? status.color.opacity(0.45) : AppTheme.hairline, lineWidth: isCurrent ? 1.5 : 1)
            )
            .scaleEffect(isCurrent ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.label) \(status.detail)")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
