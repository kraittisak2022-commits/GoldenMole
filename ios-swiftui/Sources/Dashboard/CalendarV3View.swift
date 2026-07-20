import SwiftUI

/// ปฏิทินการทำงาน (V.3) — mirrors the web calendar dashboard
/// (`src/modules/Dashboard/CalendarView.tsx`).
///
/// Sunday-first month grid, net-based day coloring, holiday/appointment/leave
/// indicators, monthly income/expense summary, and a rich selected-day detail
/// sheet. Read-only: adding/deleting calendar entries requires the Supabase
/// write layer, which is intentionally out of scope here.
struct CalendarV3View: View {
    let transactions: [Transaction]
    let employees: [Employee]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visibleMonth: Date = {
        // Normalize to the 1st of the current month (matches web cursorMonth).
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    @State private var selectedDay: String?

    // Sunday-first weekday headers (matches web).
    private let weekdayLabels = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
    private let weekdayLabelsFull = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัส", "ศุกร์", "เสาร์"]

    private var days: [CalendarDayModel] {
        CalendarV3Logic.buildDays(visibleMonth: visibleMonth, transactions: transactions, employees: employees)
    }

    private var monthIncome: Double { days.reduce(0) { $0 + $1.income } }
    private var monthExpense: Double { days.reduce(0) { $0 + $1.expense } }
    private var monthNet: Double { monthIncome - monthExpense }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceXL) {
            heroCard

            SectionCard {
                legend
                calendarGrid
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: visibleMonth)
        .sheet(item: selectedDayBinding) { day in
            DayDetailSheet(day: day, onClose: { selectedDay = nil })
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 150, height: 150)
                .blur(radius: 26)
                .offset(x: 210, y: -40)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CALENDAR")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("ปฏิทินการทำงาน")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("รายรับ · รายจ่าย · วันหยุด · นัดหมาย")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                        .accessibilityHidden(true)
                }

                monthNavigation

                HStack(spacing: 10) {
                    heroMiniStat(
                        title: "รายรับ",
                        value: "฿" + DashboardAggregations.formatNumber(monthIncome),
                        tint: Color(hex: "#A7F3D0")
                    )
                    heroMiniStat(
                        title: "รายจ่าย",
                        value: "฿" + DashboardAggregations.formatNumber(monthExpense),
                        tint: Color(hex: "#FECACA")
                    )
                    heroMiniStat(
                        title: "สุทธิ",
                        value: (monthNet >= 0 ? "+" : "") + "฿" + DashboardAggregations.formatNumber(monthNet),
                        tint: .white
                    )
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXL, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.35), radius: 18, y: 8)
    }

    private func heroMiniStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    // MARK: - Month navigation

    private var monthNavigation: some View {
        HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนก่อน")

            VStack(spacing: 4) {
                Text(monthTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button { goThisMonth() } label: {
                    Text("เดือนนี้")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนถัดไป")
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceSM) {
            Text("สัญลักษณ์")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            HStack(spacing: 0) {
                legendItem(systemImage: "party.popper", color: AppTheme.expense, label: "วันหยุด")
                legendItem(systemImage: "clock", color: AppTheme.purple, label: "นัดหมาย")
                legendItem(systemImage: "sparkles", color: AppTheme.warning, label: "เหตุการณ์")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func legendItem(systemImage: String, color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Grid

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let leading = CalendarV3Logic.leadingBlankCount(visibleMonth: visibleMonth)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, d in
                Text(d)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(index == 0 ? AppTheme.expense.opacity(0.85) : AppTheme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel(weekdayLabelsFull[index])
            }
            ForEach(0..<leading, id: \.self) { i in
                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                    .fill(AppTheme.surfaceSoft.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                            .strokeBorder(AppTheme.hairline.opacity(0.5), lineWidth: 1)
                    )
                    .frame(minHeight: 68)
                    .id("blank-\(i)")
                    .accessibilityHidden(true)
            }
            ForEach(days) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: CalendarDayModel) -> some View {
        let isSelected = selectedDay == day.date
        let isToday = day.date == DashboardAggregations.todayYMD()
        let style = DayCellStyle(day: day)

        return Button {
            selectedDay = day.date
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 2) {
                    Text("\(day.day)")
                        .font(.subheadline.weight(isToday ? .bold : .semibold))
                        .foregroundStyle(isToday && !day.hasFinance ? AppTheme.brand : style.dayNumberColor)
                    Spacer(minLength: 0)
                    indicatorDots(day)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if day.income > 0 {
                        amountTag("+" + DashboardAggregations.formatNumber(day.income), color: AppTheme.income)
                    }
                    if day.expense > 0 {
                        amountTag("-" + DashboardAggregations.formatNumber(day.expense), color: AppTheme.expense)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                    .fill(isSelected ? AppTheme.brand.opacity(0.16) : style.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AppTheme.brand.opacity(0.55)
                            : (isToday ? AppTheme.brand.opacity(0.65) : style.border),
                        lineWidth: (isSelected || isToday) ? 1.6 : 1
                    )
            )
            .shadow(
                color: isSelected ? AppTheme.brand.opacity(0.18) : .clear,
                radius: 6,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func indicatorDots(_ day: CalendarDayModel) -> some View {
        HStack(spacing: 3) {
            if day.hasHoliday { dot(AppTheme.expense) }
            if day.hasAppointment { dot(AppTheme.purple) }
            if day.hasReminder { dot(AppTheme.warning) }
            if day.presentCount > 0 { dot(AppTheme.info) }
            if day.leaveCount > 0 { dot(AppTheme.warning) }
        }
        .frame(height: 6)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }

    private func amountTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.14))
            )
    }

    private func accessibilityLabel(_ day: CalendarDayModel) -> String {
        var parts = ["วันที่ \(day.day)"]
        if day.income > 0 { parts.append("รายรับ \(DashboardAggregations.formatNumber(day.income))") }
        if day.expense > 0 { parts.append("รายจ่าย \(DashboardAggregations.formatNumber(day.expense))") }
        if day.hasHoliday { parts.append("วันหยุด") }
        if day.hasAppointment { parts.append("มีนัดหมาย") }
        if day.presentCount > 0 { parts.append("มาทำงาน \(day.presentCount)") }
        if day.leaveCount > 0 { parts.append("ลา \(day.leaveCount)") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private var selectedDayBinding: Binding<CalendarDayModel?> {
        Binding(
            get: { days.first(where: { $0.date == selectedDay }) },
            set: { newValue in selectedDay = newValue?.date }
        )
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .buddhist)
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: visibleMonth)
    }

    private func shiftMonth(_ delta: Int) {
        visibleMonth = DashboardAggregations.gregorian.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
        selectedDay = nil
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        visibleMonth = cal.date(from: comps) ?? Date()
        selectedDay = nil
    }
}

// MARK: - Day cell styling (net-based, matches web)

private struct DayCellStyle {
    let background: Color
    let border: Color
    let dayNumberColor: Color

    init(day: CalendarDayModel) {
        if day.hasFinance {
            if day.net > 0 {
                background = AppTheme.income.opacity(0.12)
                border = AppTheme.income.opacity(0.28)
                dayNumberColor = AppTheme.income
            } else if day.net < 0 {
                background = AppTheme.expense.opacity(0.10)
                border = AppTheme.expense.opacity(0.28)
                dayNumberColor = AppTheme.expense
            } else {
                background = AppTheme.warning.opacity(0.12)
                border = AppTheme.warning.opacity(0.28)
                dayNumberColor = AppTheme.warning
            }
        } else {
            background = AppTheme.surfaceSoft
            border = AppTheme.hairline
            dayNumberColor = AppTheme.inkSecondary
        }
    }
}

// MARK: - Selected-day detail sheet

private struct DayDetailSheet: View {
    let day: CalendarDayModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                    header
                    if !day.calendarRows.isEmpty { calendarSection }
                    financeTotals
                    attendanceSection
                    activitySection
                    ledgerSection
                }
                .padding(AppTheme.spaceLG)
            }
            .background(DashboardBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("รายละเอียดวัน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { onClose() }
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                .offset(x: 240, y: -30)

            VStack(alignment: .leading, spacing: 6) {
                Text("DAY DETAIL")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                Text(longThaiDate(day.date))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("สรุปกิจกรรมและข้อมูลการเงิน")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXL, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.28), radius: 14, y: 6)
    }

    private var calendarSection: some View {
        SectionCard("วันหยุด / นัดหมาย / เหตุการณ์", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(day.calendarRows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        PillBadge(text: row.kindLabel, color: kindColor(row.subCategory))
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let time = row.eventTime, !time.isEmpty {
                            Label("\(time) น.", systemImage: "clock")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.purple)
                        }
                        if let note = row.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                            .fill(AppTheme.surfaceSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                            .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var financeTotals: some View {
        HStack(spacing: AppTheme.spaceMD) {
            totalTile(title: "รายรับ", value: "+" + DashboardAggregations.formatNumber(day.income), color: AppTheme.income)
            totalTile(title: "รายจ่าย", value: "-" + DashboardAggregations.formatNumber(day.expense), color: AppTheme.expense)
            totalTile(
                title: "ยอดสุทธิ",
                value: (day.net > 0 ? "+" : "") + DashboardAggregations.formatNumber(day.net),
                color: day.net >= 0 ? AppTheme.brand : AppTheme.warning
            )
        }
    }

    private func totalTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
    }

    private var attendanceSection: some View {
        SectionCard("การมาทำงาน", systemImage: "person.2.fill") {
            HStack(spacing: AppTheme.spaceMD) {
                attendanceCard(count: day.presentCount, title: "มาทำงาน", subtitle: "พนักงานเข้ากะ", color: AppTheme.info)
                attendanceCard(
                    count: day.leaveCount,
                    title: "ลางาน",
                    subtitle: day.leaveNames.isEmpty ? "-" : day.leaveNames.joined(separator: ", "),
                    color: AppTheme.warning
                )
            }
        }
    }

    private func attendanceCard(count: Int, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var activitySection: some View {
        SectionCard("บันทึกกิจกรรมแทรกเตอร์ / ทราย", systemImage: "gearshape.2.fill") {
            let isEmpty = day.machineLogs.isEmpty && day.sandLogs.isEmpty && day.eventLogs.isEmpty
            if isEmpty {
                EmptyStateView(title: "ไม่มีบันทึกกิจกรรมพิเศษสำหรับวันนี้", systemImage: "tray")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(day.machineLogs) { t in activityRow(t, systemImage: "gearshape.2.fill", tint: AppTheme.vehicle, text: machineText(t)) }
                    ForEach(day.sandLogs) { t in activityRow(t, systemImage: "drop.fill", tint: AppTheme.dailyLog, text: sandText(t)) }
                    ForEach(day.eventLogs) { t in activityRow(t, systemImage: "pin.fill", tint: AppTheme.warning, text: t.description) }
                }
            }
        }
    }

    private func activityRow(_ t: Transaction, systemImage: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var ledgerSection: some View {
        SectionCard("รายการเดินบัญชี (ไม่รวมรายการปฏิทิน)", systemImage: "list.bullet.rectangle") {
            if day.financeTransactions.isEmpty {
                EmptyStateView(title: "ไม่มีรายการเดินบัญชี", systemImage: "tray")
            } else {
                VStack(spacing: 8) {
                    ForEach(day.financeTransactions) { t in ledgerRow(t) }
                }
            }
        }
    }

    private func ledgerRow(_ t: Transaction) -> some View {
        let isIncome = t.type == .income
        let amountColor: Color = isIncome ? AppTheme.income : (t.category == "Leave" ? AppTheme.warning : AppTheme.expense)
        let amountText: String = t.amount > 0
            ? "฿" + DashboardAggregations.formatNumber(t.amount)
            : (t.category == "Leave" ? "ลา" : "-")
        return HStack(spacing: 10) {
            Text(isIncome ? "+" : "-")
                .font(.headline)
                .foregroundStyle(amountColor)
                .frame(width: 34, height: 34)
                .background(amountColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(t.description)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Text(t.category + (t.subCategory.map { " • \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
            Text(amountText)
                .font(.subheadline.bold())
                .foregroundStyle(amountColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Detail helpers

    private func kindColor(_ sub: String) -> Color {
        switch sub {
        case "Holiday": return AppTheme.expense
        case "Appointment": return AppTheme.purple
        default: return AppTheme.warning
        }
    }

    private func machineText(_ t: Transaction) -> String {
        if t.subCategory == "VehicleTrip" {
            var s = t.description.isEmpty ? "เที่ยวรถ" : t.description
            if let details = t.workDetails, !details.isEmpty { s += "\n\(details)" }
            if t.amount > 0 { s += "\n฿\(DashboardAggregations.formatNumber(t.amount))" }
            return s
        }
        let machine = t.machineId ?? "เครื่องจักร"
        let hours = t.machineHours ?? 0
        var s = "\(machine) (\(DashboardAggregations.formatNumber(hours)) ชม.)"
        let detail = t.note ?? t.description
        if !detail.isEmpty { s += "\n\(detail)" }
        return s
    }

    private func sandText(_ t: Transaction) -> String {
        let total = (t.sandMorning ?? 0) + (t.sandAfternoon ?? 0)
        let machine = t.sandMachineType == "Old" ? "เครื่องเก่า" : (t.sandMachineType == "New" ? "เครื่องใหม่" : "-")
        var s = "ล้างทราย \(DashboardAggregations.formatNumber(total)) คิว (\(machine))"
        s += "\nเช้า: \(DashboardAggregations.formatNumber(t.sandMorning ?? 0)) คิว / บ่าย: \(DashboardAggregations.formatNumber(t.sandAfternoon ?? 0)) คิว"
        if let transport = t.sandTransport, transport > 0 {
            s += "\nขน: \(DashboardAggregations.formatNumber(transport)) คิว"
        }
        if t.amount > 0 { s += "\n฿\(DashboardAggregations.formatNumber(t.amount))" }
        return s
    }

    private func longThaiDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Bangkok")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(dateStr.prefix(10))) else { return dateStr }
        let display = DateFormatter()
        display.calendar = Calendar(identifier: .buddhist)
        display.locale = Locale(identifier: "th_TH")
        display.timeZone = TimeZone(identifier: "Asia/Bangkok")
        display.dateFormat = "EEEE d MMMM yyyy"
        return display.string(from: date)
    }
}
