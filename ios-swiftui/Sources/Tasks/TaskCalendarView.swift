import SwiftUI

/// Month grid of task load. Each cell shows how many tasks fall on that day and colours
/// itself by whether anything is still open. Mirrors the layout of `CalendarV3View`.
struct TaskCalendarView: View {
    let tasks: [WorkTask]
    @Binding var selectedDay: String

    @State private var visibleMonth: Date = {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    private let weekdayLabels = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
    private let weekdayLabelsFull = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัส", "ศุกร์", "เสาร์"]

    private struct DayLoad {
        let date: String
        let day: Int
        let total: Int
        let open: Int
        let hasFocus: Bool
        let hasUrgent: Bool
    }

    private var days: [DayLoad] {
        let cal = DashboardAggregations.gregorian
        let year = cal.component(.year, from: visibleMonth)
        let month = cal.component(.month, from: visibleMonth)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first)
        else { return [] }

        return range.map { d in
            let key = String(format: "%04d-%02d-%02d", year, month, d)
            let onDay = tasks.filter { $0.covers(day: key) }
            return DayLoad(
                date: key,
                day: d,
                total: onDay.count,
                open: onDay.filter { !$0.isDone }.count,
                hasFocus: onDay.contains { $0.isFocus },
                hasUrgent: onDay.contains { $0.priority == .urgent && !$0.isDone }
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            monthNavigation
            grid
            legend
        }
    }

    // MARK: - Month navigation

    private var monthNavigation: some View {
        HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: {
                navIcon("chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนก่อน")

            VStack(spacing: 4) {
                Text(monthTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button { goThisMonth() } label: {
                    Text("เดือนนี้")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.brand.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            Button { shiftMonth(1) } label: {
                navIcon("chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนถัดไป")
        }
    }

    private func navIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.brand)
            .frame(width: 36, height: 36)
            .background(Circle().fill(AppTheme.surfaceSoft))
            .overlay(Circle().strokeBorder(AppTheme.hairline, lineWidth: 1))
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let leading = CalendarV3Logic.leadingBlankCount(visibleMonth: visibleMonth)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(index == 0 ? AppTheme.expense.opacity(0.85) : AppTheme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel(weekdayLabelsFull[index])
            }
            ForEach(0..<leading, id: \.self) { i in
                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                    .fill(AppTheme.surfaceSoft.opacity(0.45))
                    .frame(minHeight: 54)
                    .id("task-blank-\(i)")
                    .accessibilityHidden(true)
            }
            ForEach(days, id: \.date) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: DayLoad) -> some View {
        let isSelected = day.date == selectedDay
        let isToday = day.date == DashboardAggregations.todayYMD()
        let accent: Color = day.open > 0
            ? (day.hasUrgent ? AppTheme.expense : AppTheme.warning)
            : (day.total > 0 ? AppTheme.income : AppTheme.inkMuted)

        return Button {
            selectedDay = day.date
        } label: {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : (isToday ? AppTheme.brand : AppTheme.ink))
                if day.total > 0 {
                    Text("\(day.total)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .white : accent)
                } else {
                    Text(" ")
                        .font(.system(size: 10, weight: .bold))
                }
                Circle()
                    .fill(day.hasFocus ? (isSelected ? Color.white : AppTheme.purple) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                    .fill(isSelected ? AppTheme.brand : accent.opacity(day.total > 0 ? 0.12 : 0.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? AppTheme.brand.opacity(0.55) : AppTheme.hairline,
                        lineWidth: isToday && !isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day))
    }

    private func accessibilityLabel(_ day: DayLoad) -> String {
        guard day.total > 0 else {
            return "\(DashboardAggregations.thaiDateLong(day.date)) ไม่มีงาน"
        }
        return "\(DashboardAggregations.thaiDateLong(day.date)) มี \(day.total) งาน ค้าง \(day.open) งาน"
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: AppTheme.warning, label: "ยังมีงานค้าง")
            legendItem(color: AppTheme.income, label: "เสร็จหมด")
            legendItem(color: AppTheme.purple, label: "มีงานโฟกัส")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .buddhist)
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: visibleMonth)
    }

    private func shiftMonth(_ delta: Int) {
        let cal = DashboardAggregations.gregorian
        visibleMonth = cal.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        visibleMonth = cal.date(from: comps) ?? Date()
        selectedDay = DashboardAggregations.todayYMD()
    }
}
