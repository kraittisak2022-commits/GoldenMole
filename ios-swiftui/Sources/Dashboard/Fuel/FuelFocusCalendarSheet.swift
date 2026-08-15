import SwiftUI
import UIKit

/// Focus-date calendar for Home > น้ํามัน with per-day activity marks.
struct FuelFocusCalendarSheet: View {
    @Binding var selection: Date
    let transactions: [Transaction]
    var transactionsRevision: Int = 0
    var onDismiss: () -> Void

    @State private var visibleMonth: Date
    @State private var marks: [String: FuelLogic.DayFuelMark] = [:]

    private let weekdayLabels = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
    private let weekdayLabelsFull = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัส", "ศุกร์", "เสาร์"]

    private static let stockInColor = Color(hex: "#0d9488")
    private static let withdrawColor = Color(hex: "#ea580c")
    private static let sandSieveColor = Color(hex: "#DB2777")
    private static let macroColor = Color(hex: "#0F766E")
    private static let accent = Color(hex: "#0d9488")

    private var todayYmd: String { DashboardAggregations.todayYMD() }
    private var selectedYmd: String { DashboardAggregations.formatYMD(selection) }

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
        let mark: FuelLogic.DayFuelMark
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
        transactionsRevision: Int = 0,
        onDismiss: @escaping () -> Void
    ) {
        self._selection = selection
        self.transactions = transactions
        self.transactionsRevision = transactionsRevision
        self.onDismiss = onDismiss
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: selection.wrappedValue)
        _visibleMonth = State(initialValue: cal.date(from: comps) ?? selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                monthNavigation
                legend
                calendarGrid
                Button {
                    selectToday()
                } label: {
                    Label("วันนี้", systemImage: "sun.max.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Self.accent)
                .padding(.horizontal, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(AppTheme.pageTop.ignoresSafeArea())
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
        .presentationDetents([.medium, .large])
    }

    // MARK: - Month nav

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
                            .foregroundStyle(Self.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                guard canGoNextMonth else { return }
                withAnimation(.snappy(duration: 0.25)) { shiftMonth(1) }
            } label: {
                navIcon("chevron.right")
                    .opacity(canGoNextMonth ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!canGoNextMonth)
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

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                legendChip(color: Self.stockInColor, label: "เพิ่มน้ำมัน")
                legendChip(color: Self.withdrawColor, label: "เบิกน้ำมัน")
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                legendChip(color: Self.sandSieveColor, label: "เครื่องร่อน")
                legendChip(color: Self.macroColor, label: "แม็คโคร")
                Spacer(minLength: 0)
            }
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
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
                        .frame(minHeight: 52)
                        .id("fuel-blank-\(i)")
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

    private func dayCell(_ day: DayCell) -> some View {
        let isSelected = day.date == selectedYmd
        let isToday = day.date == todayYmd

        return Button {
            guard !day.isFuture else { return }
            selectDay(day.date)
        } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.system(size: 14, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(dayNumberColor(isSelected: isSelected, isToday: isToday, isFuture: day.isFuture))

                markDots(day.mark, isSelected: isSelected)
                    .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(cellBackground(isSelected: isSelected, isToday: isToday))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? Self.accent.opacity(0.45) : Color.clear,
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

    private func markDots(_ mark: FuelLogic.DayFuelMark, isSelected: Bool) -> some View {
        let colors: [Color] = [
            mark.stockIn ? Self.stockInColor : nil,
            mark.withdraw ? Self.withdrawColor : nil,
            mark.sandSieve ? Self.sandSieveColor : nil,
            mark.macroUsage ? Self.macroColor : nil,
        ].compactMap { $0 }

        return HStack(spacing: 2) {
            if colors.isEmpty {
                Color.clear.frame(width: 5, height: 5)
            } else {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.92) : color)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func dayNumberColor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isSelected { return .white }
        if isFuture { return AppTheme.inkMuted }
        if isToday { return Self.accent }
        return AppTheme.ink
    }

    private func cellBackground(isSelected: Bool, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isSelected
                    ? Self.accent
                    : (isToday ? Self.accent.opacity(0.10) : Color.clear)
            )
    }

    private func accessibilityLabel(_ day: DayCell) -> String {
        var parts = ["วันที่ \(day.day)"]
        if day.date == todayYmd { parts.append("วันนี้") }
        if day.isFuture { parts.append("ยังมาไม่ถึง") }
        if day.mark.stockIn { parts.append("มีเพิ่มน้ำมัน") }
        if day.mark.withdraw { parts.append("มีเบิกน้ำมัน") }
        if day.mark.sandSieve { parts.append("มีเครื่องร่อน") }
        if day.mark.macroUsage { parts.append("มีใช้แม็คโคร") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func rebuildMarks() {
        let month = visibleMonth
        let txs = transactions
        Task(priority: .userInitiated) {
            let next = await Task.detached(priority: .userInitiated) {
                FuelLogic.dayFuelMarks(inMonth: month, transactions: txs)
            }.value
            marks = next
        }
    }

    private func shiftMonth(_ delta: Int) {
        let cal = DashboardAggregations.gregorian
        if let next = cal.date(byAdding: .month, value: delta, to: visibleMonth) {
            if delta > 0 {
                let nextMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: next)) ?? next
                let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
                if nextMonthStart > thisMonthStart { return }
            }
            visibleMonth = next
        }
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        visibleMonth = cal.date(from: comps) ?? Date()
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
