import SwiftUI
import UIKit

/// Month grid of task load. Each cell shows tasks **due that day** (matching the day list),
/// not the full weekly/monthly/yearly scope span — so one yearly open task no longer paints
/// every day as "งานค้าง 1".
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
    private var today: String { DashboardAggregations.todayYMD() }

    private struct DayLoad: Identifiable {
        var id: String { date }
        let date: String
        let day: Int
        /// Tasks whose `dueDate` is this day.
        let dueTotal: Int
        let dueOpen: Int
        /// Overdue carry-overs counted only on today.
        let carryOpen: Int
        let hasFocus: Bool
        let hasUrgent: Bool

        var open: Int { dueOpen + carryOpen }
        var total: Int { dueTotal + carryOpen }
        var allDone: Bool { total > 0 && open == 0 }
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
            let due = tasks.filter { $0.dueDate == key }
            let carryOpen: Int
            if key == today {
                carryOpen = tasks.filter { !$0.isDone && $0.scopeEndDate < key }.count
            } else {
                carryOpen = 0
            }
            return DayLoad(
                date: key,
                day: d,
                dueTotal: due.count,
                dueOpen: due.filter { !$0.isDone }.count,
                carryOpen: carryOpen,
                hasFocus: due.contains { $0.isFocus && !$0.isDone },
                hasUrgent: due.contains { $0.priority == .urgent && !$0.isDone }
            )
        }
    }

    private var monthOpen: Int { days.reduce(0) { $0 + $1.open } }
    private var monthDue: Int { days.reduce(0) { $0 + $1.dueTotal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            monthNavigation
            monthSummary
            grid
            legend
        }
    }

    // MARK: - Month navigation

    private var monthNavigation: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.snappy(duration: 0.25)) { shiftMonth(-1) } } label: {
                navIcon("chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนก่อน")

            VStack(spacing: 2) {
                Text(monthTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !isCurrentMonth {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { goThisMonth() }
                    } label: {
                        Text("กลับเดือนนี้")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Button { withAnimation(.snappy(duration: 0.25)) { shiftMonth(1) } } label: {
                navIcon("chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนถัดไป")
        }
    }

    private func navIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.inkSecondary)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
    }

    private var monthSummary: some View {
        HStack(spacing: 10) {
            summaryChip(
                value: "\(monthDue)",
                label: "กำหนดเดือนนี้",
                tint: AppTheme.brand
            )
            summaryChip(
                value: "\(monthOpen)",
                label: monthOpen == 0 ? "ไม่มีค้าง" : "ยังค้าง",
                tint: monthOpen == 0 ? AppTheme.income : AppTheme.warning
            )
            Spacer(minLength: 0)
            if selectedDay.hasPrefix(monthPrefix) {
                Text(selectedDayLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.surfaceSoft))
            }
        }
    }

    private func summaryChip(value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(tint.opacity(0.1))
        )
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let leading = CalendarV3Logic.leadingBlankCount(visibleMonth: visibleMonth)
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == 0 ? AppTheme.expense.opacity(0.8) : AppTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)
                        .accessibilityLabel(weekdayLabelsFull[index])
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leading, id: \.self) { i in
                    Color.clear
                        .frame(minHeight: 48)
                        .id("task-blank-\(i)")
                        .accessibilityHidden(true)
                }
                ForEach(days) { day in
                    dayCell(day)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfaceSoft.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func dayCell(_ day: DayLoad) -> some View {
        let isSelected = day.date == selectedDay
        let isToday = day.date == today
        let status = cellStatus(day)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day.date }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.system(size: 14, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(dayNumberColor(isSelected: isSelected, isToday: isToday, status: status))

                statusDots(day, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(cellBackground(isSelected: isSelected, isToday: isToday, status: status))
            .overlay(cellOverlay(isSelected: isSelected, isToday: isToday))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private enum CellStatus {
        case empty
        case open
        case urgent
        case done
    }

    private func cellStatus(_ day: DayLoad) -> CellStatus {
        if day.open > 0 {
            return day.hasUrgent ? .urgent : .open
        }
        if day.total > 0 { return .done }
        return .empty
    }

    private func dayNumberColor(isSelected: Bool, isToday: Bool, status: CellStatus) -> Color {
        if isSelected { return .white }
        if isToday { return AppTheme.brand }
        switch status {
        case .urgent: return AppTheme.expense
        case .open: return AppTheme.ink
        case .done: return AppTheme.income
        case .empty: return AppTheme.inkSecondary
        }
    }

    @ViewBuilder
    private func statusDots(_ day: DayLoad, isSelected: Bool) -> some View {
        let maxDots = 3
        if day.total == 0 {
            Circle()
                .fill(Color.clear)
                .frame(width: 5, height: 5)
        } else {
            HStack(spacing: 3) {
                ForEach(0..<min(day.total, maxDots), id: \.self) { index in
                    Circle()
                        .fill(dotColor(day, index: index, isSelected: isSelected))
                        .frame(width: 5, height: 5)
                }
                if day.total > maxDots {
                    Text("+\(day.total - maxDots)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : AppTheme.inkMuted)
                }
            }
            .frame(height: 8)
        }
    }

    private func dotColor(_ day: DayLoad, index: Int, isSelected: Bool) -> Color {
        if isSelected { return .white.opacity(0.95) }
        // Paint open dots first, then done.
        if index < day.open {
            return day.hasUrgent && index == 0 ? AppTheme.expense : AppTheme.warning
        }
        return AppTheme.income
    }

    @ViewBuilder
    private func cellBackground(isSelected: Bool, isToday: Bool, status: CellStatus) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(backgroundFill(isSelected: isSelected, isToday: isToday, status: status))
    }

    private func backgroundFill(isSelected: Bool, isToday: Bool, status: CellStatus) -> Color {
        if isSelected {
            return AppTheme.brand
        }
        switch status {
        case .urgent: return AppTheme.expense.opacity(0.12)
        case .open: return AppTheme.warning.opacity(0.12)
        case .done: return AppTheme.income.opacity(0.1)
        case .empty: return isToday ? AppTheme.brand.opacity(0.06) : Color.clear
        }
    }

    @ViewBuilder
    private func cellOverlay(isSelected: Bool, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isSelected
                    ? Color.clear
                    : (isToday ? AppTheme.brand.opacity(0.55) : Color.clear),
                lineWidth: isToday && !isSelected ? 1.5 : 0
            )
    }

    private func accessibilityLabel(_ day: DayLoad) -> String {
        let date = DashboardAggregations.thaiDateLong(day.date)
        if day.total == 0 { return "\(date) ไม่มีงาน" }
        var parts = ["\(date) กำหนด \(day.dueTotal) งาน"]
        if day.dueOpen > 0 { parts.append("ค้าง \(day.dueOpen)") }
        if day.carryOpen > 0 { parts.append("ยกมา \(day.carryOpen)") }
        if day.allDone { parts.append("เสร็จหมด") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: AppTheme.warning, label: "มีงานค้าง")
            legendItem(color: AppTheme.income, label: "เสร็จหมด")
            legendItem(color: AppTheme.expense, label: "ด่วน")
            Spacer(minLength: 0)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
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

    private var monthPrefix: String {
        let cal = DashboardAggregations.gregorian
        let y = cal.component(.year, from: visibleMonth)
        let m = cal.component(.month, from: visibleMonth)
        return String(format: "%04d-%02d", y, m)
    }

    private var isCurrentMonth: Bool {
        today.hasPrefix(monthPrefix)
    }

    private var selectedDayLabel: String {
        if selectedDay == today { return "เลือก: วันนี้" }
        let parts = selectedDay.split(separator: "-")
        guard parts.count == 3, let d = Int(parts[2]) else { return "" }
        return "เลือก: \(d)"
    }

    private func shiftMonth(_ delta: Int) {
        let cal = DashboardAggregations.gregorian
        visibleMonth = cal.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        visibleMonth = cal.date(from: comps) ?? Date()
        selectedDay = today
    }
}
