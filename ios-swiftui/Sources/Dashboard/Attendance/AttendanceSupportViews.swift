import SwiftUI

struct AttendanceEmployeeChip: View {
    let name: String
    let selected: Bool
    let placed: Bool
    let accent: Color
    var onTap: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(placed || selected ? accent : AppTheme.ink)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(selected ? accent.opacity(0.22) : (placed ? accent.opacity(0.10) : AppTheme.surfaceSoft))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    selected ? accent : (placed ? accent.opacity(0.45) : AppTheme.inkMuted.opacity(0.25)),
                    lineWidth: selected ? 1.5 : 1
                )
        )
    }
}

struct AttendanceBucketCard: View {
    let bucket: AttendanceBucket
    let employees: [Employee]
    let pickedIds: Set<String>
    let onDropZoneTap: () -> Void
    let onChipTap: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(bucket.shortTitle)
                    .font(.headline)
                    .foregroundStyle(bucket.accent)
                Spacer(minLength: 0)
                Text("\(employees.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(bucket.accent)
            }

            Button(action: onDropZoneTap) {
                VStack(alignment: .leading, spacing: 8) {
                    if employees.isEmpty {
                        Text(pickedIds.isEmpty ? "แตะชื่อแล้วกดที่นี่" : "แตะเพื่อย้าย \(pickedIds.count) คนมาที่นี่")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    } else {
                        FlowEmployeeChips(
                            employees: employees,
                            pickedIds: pickedIds,
                            accent: bucket.accent,
                            placed: true,
                            onChipTap: onChipTap,
                            onRemove: onRemove
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(bucket.accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            pickedIds.isEmpty ? bucket.accent.opacity(0.25) : bucket.accent.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1.5, dash: pickedIds.isEmpty ? [] : [6, 4])
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(bucket.accent.opacity(0.3), lineWidth: 1)
        )
    }
}

struct AttendancePoolCard: View {
    let title: String
    let employees: [Employee]
    let placedIds: Set<String>
    let pickedIds: Set<String>
    let accent: Color
    let onTap: (String) -> Void
    let onReturnToPool: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                if !pickedIds.isEmpty {
                    Button("คืนพูล (\(pickedIds.count))", action: onReturnToPool)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.expense)
                }
            }

            if employees.isEmpty {
                Text("ไม่มีรายชื่อในกลุ่มนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.vertical, 8)
            } else {
                FlowEmployeeChips(
                    employees: employees,
                    pickedIds: pickedIds,
                    accent: accent,
                    placedLookup: { placedIds.contains($0) },
                    onChipTap: onTap,
                    onRemove: nil
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }
}

/// Simple wrapping chip layout without LazyVGrid complexity.
private struct FlowEmployeeChips: View {
    let employees: [Employee]
    let pickedIds: Set<String>
    let accent: Color
    var placed: Bool = false
    var placedLookup: ((String) -> Bool)? = nil
    let onChipTap: (String) -> Void
    let onRemove: ((String) -> Void)?

    var body: some View {
        FlexibleChipWrap(spacing: 8) {
            ForEach(employees) { emp in
                let isPlaced = placed || (placedLookup?(emp.id) ?? false)
                AttendanceEmployeeChip(
                    name: emp.displayName,
                    selected: pickedIds.contains(emp.id),
                    placed: isPlaced,
                    accent: accent,
                    onTap: { onChipTap(emp.id) },
                    onRemove: onRemove.map { handler in { handler(emp.id) } }
                )
            }
        }
    }
}

/// Lightweight wrap layout for chips.
struct FlexibleChipWrap<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        _FlexibleChipWrapLayout(spacing: spacing) {
            content()
        }
    }
}

private struct _FlexibleChipWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            height = max(height, y + rowHeight)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
