import SwiftUI
import UIKit

/// Focus-date calendar for Real-time เที่ยวรถ / ร่อนทราย with per-day activity marks.
struct RealtimeFocusCalendarSheet: View {
    @Binding var selection: Date
    let transactions: [Transaction]
    let employees: [Employee]
    var transactionsRevision: Int = 0
    var onDismiss: () -> Void

    @State private var visibleMonth: Date
    @State private var marks: [String: CountRecordLogic.DayOpsMark] = [:]

    private let weekdayLabels = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
    private let weekdayLabelsFull = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัส", "ศุกร์", "เสาร์"]

    private static let tripColor = Color(hex: "#2563EB")
    private static let sandColor = Color(hex: "#DB2777")

    private var todayYmd: String { DashboardAggregations.todayYMD() }
    private var selectedYmd: String { DashboardAggregations.formatYMD(selection) }

    private var monthKey: String {
        let cal = DashboardAggregations.gregorian
        let y = cal.component(.year, from: visibleMonth)
        let m = cal.component(.month, from: visibleMonth)
        return String(format: "%04d-%02d", y, m)
    }

    private var monthTitle: String {
        let cal = DashboardAggregations.gregorian
        let y = cal.component(.year, from: visibleMonth)
        let m = cal.component(.month, from: visibleMonth)
        let thaiMonths = [
            "", "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
            "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม",
        ]
        let name = (m >= 1 && m <= 12) ? thaiMonths[m] : "\(m)"
        return "\(name) \(y + 543)"
    }

    private var isCurrentMonth: Bool {
        let cal = DashboardAggregations.gregorian
        return cal.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    private var canGoNextMonth: Bool {
        let cal = DashboardAggregations.gregorian
        guard let next = cal.date(byAdding: .month, value: 1, to: visibleMonth) else { return false }
        let nextStart = cal.date(from: cal.dateComponents([.year, .month], from: next)) ?? next
        let thisStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return nextStart <= thisStart
    }

    private struct DayCell: Identifiable {
        var id: String { date }
        let date: String
        let day: Int
        let mark: CountRecordLogic.DayOpsMark
        let isFuture: Bool
    }

    private var days: [DayCell] {
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
            return DayCell(
                date: key,
                day: d,
                mark: marks[key] ?? .none,
                isFuture: key > todayYmd
            )
        }
    }

    init(
        selection: Binding<Date>,
        transactions: [Transaction],
        employees: [Employee],
        transactionsRevision: Int = 0,
        onDismiss: @escaping () -> Void
    ) {
        self._selection = selection
        self.transactions = transactions
        self.employees = employees
        self.transactionsRevision = transactionsRevision
        self.onDismiss = onDismiss
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: selection.wrappedValue)
        _visibleMonth = State(initialValue: cal.date(from: comps) ?? selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthNavigation
                    legend
                    calendarGrid
                    Text("ปัดซ้าย/ขวาบนปฏิทินเพื่อเปลี่ยนเดือน")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    Button {
                        selectToday()
                    } label: {
                        Label("วันนี้", systemImage: "sun.max.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Self.tripColor)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(AppTheme.pageTop)
            // Avoid nav title "กำลังดู" colliding with the month label below.
            .navigationTitle("เลือกวันที่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { rebuildMarks() }
            .onChange(of: visibleMonth) { _, _ in rebuildMarks() }
            .onChange(of: transactionsRevision) { _, _ in rebuildMarks() }
            .onChange(of: transactions.count) { _, _ in rebuildMarks() }
        }
        .presentationDetents([.large, .fraction(0.92)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Month nav

    private var monthNavigation: some View {
        HStack(spacing: 12) {
            Button {
                shiftMonth(-1)
            } label: {
                navIcon("chevron.left")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("เดือนก่อน")

            VStack(spacing: 2) {
                Text(monthTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .id(monthKey)
                if !isCurrentMonth {
                    Button {
                        goThisMonth()
                    } label: {
                        Text("กลับเดือนนี้")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Self.tripColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                guard canGoNextMonth else { return }
                shiftMonth(1)
            } label: {
                navIcon("chevron.right")
                    .opacity(canGoNextMonth ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(!canGoNextMonth)
            .accessibilityLabel("เดือนถัดไป")
        }
        .padding(.vertical, 4)
    }

    private func navIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.inkSecondary)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            legendChip(colors: [Self.tripColor], label: "เที่ยวรถ")
            legendChip(colors: [Self.sandColor], label: "ร่อนทราย")
            legendChip(colors: [Self.tripColor, Self.sandColor], label: "ทั้งสอง")
            Spacer(minLength: 0)
        }
    }

    private func legendChip(colors: [Color], label: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 7, height: 7)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
    }

    // MARK: - Grid

    private var calendarGrid: some View {
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
                        .id("\(monthKey)-blank-\(i)")
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
        .contentShape(Rectangle())
        .id(monthKey)
        // simultaneous so day cells still receive taps; horizontal threshold filters scroll.
        .simultaneousGesture(monthSwipeGesture)
        .accessibilityHint("ปัดซ้ายหรือขวาเพื่อเปลี่ยนเดือน")
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Prefer horizontal swipes so vertical ScrollView still works.
                guard abs(dx) > abs(dy) * 1.4, abs(dx) > 40 else { return }
                if dx > 0 {
                    shiftMonth(-1)
                } else if canGoNextMonth {
                    shiftMonth(1)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
    }

    private func dayCell(_ day: DayCell) -> some View {
        let isSelected = day.date == selectedYmd
        let isToday = day.date == todayYmd

        return Button {
            guard !day.isFuture else { return }
            selectDay(day.date)
        } label: {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(.system(size: 14, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(dayNumberColor(isSelected: isSelected, isToday: isToday, isFuture: day.isFuture))

                markDots(day.mark, isSelected: isSelected)
                    .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(cellBackground(isSelected: isSelected, isToday: isToday))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? Self.tripColor.opacity(0.45) : Color.clear,
                        lineWidth: 1.2
                    )
            )
            .contentShape(Rectangle())
            .opacity(day.isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func markDots(_ mark: CountRecordLogic.DayOpsMark, isSelected: Bool) -> some View {
        HStack(spacing: 3) {
            switch mark {
            case .none:
                Color.clear.frame(width: 6, height: 6)
            case .tripOnly:
                Circle()
                    .fill(isSelected ? Color.white : Self.tripColor)
                    .frame(width: 6, height: 6)
            case .sandOnly:
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.92) : Self.sandColor)
                    .frame(width: 6, height: 6)
            case .both:
                Circle()
                    .fill(isSelected ? Color.white : Self.tripColor)
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.85) : Self.sandColor)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func dayNumberColor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isSelected { return .white }
        if isFuture { return AppTheme.inkMuted }
        if isToday { return Self.tripColor }
        return AppTheme.ink
    }

    private func cellBackground(isSelected: Bool, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isSelected
                    ? Self.tripColor
                    : (isToday ? Self.tripColor.opacity(0.10) : Color.clear)
            )
    }

    private func accessibilityLabel(_ day: DayCell) -> String {
        var parts = ["วันที่ \(day.day)"]
        if day.date == todayYmd { parts.append("วันนี้") }
        if day.isFuture { parts.append("ยังมาไม่ถึง") }
        switch day.mark {
        case .none: break
        case .tripOnly: parts.append("มีเที่ยวรถ")
        case .sandOnly: parts.append("มีร่อนทราย")
        case .both: parts.append("มีเที่ยวรถและร่อนทราย")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func rebuildMarks() {
        marks = CountRecordLogic.dayOpsMarks(
            inMonth: visibleMonth,
            transactions: transactions,
            employees: employees
        )
    }

    private func shiftMonth(_ delta: Int) {
        let cal = DashboardAggregations.gregorian
        guard let next = cal.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        if delta > 0 {
            let nextMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: next)) ?? next
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
            if nextMonthStart > thisMonthStart { return }
        }
        // Normalize to month start so identity/grid refresh stays stable.
        let normalized = cal.date(from: cal.dateComponents([.year, .month], from: next)) ?? next
        withAnimation(.snappy(duration: 0.25)) {
            visibleMonth = normalized
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        withAnimation(.snappy(duration: 0.25)) {
            visibleMonth = cal.date(from: comps) ?? Date()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func selectToday() {
        selectDay(todayYmd)
    }

    private func selectDay(_ ymd: String) {
        guard ymd <= todayYmd else { return }
        let cal = DashboardAggregations.gregorian
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let date = cal.date(from: comps) else { return }
        selection = date
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onDismiss()
    }
}
