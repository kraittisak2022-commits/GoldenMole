import SwiftUI
import UIKit

/// ปฏิทินการทำงาน (V.3) — month grid + day-detail sheet.
///
/// Read-only: adding/deleting calendar entries requires the Supabase write layer.
struct CalendarV3View: View {
    let transactions: [Transaction]
    let employees: [Employee]
    /// Notifies parent (e.g. Home) when a day cell is selected — YMD string.
    var onDaySelected: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visibleMonth: Date = {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    @State private var selectedDay: String?
    @State private var days: [CalendarDayModel] = []
    @State private var isBuildingDays = false
    @State private var buildTask: Task<Void, Never>?

    private let weekdayLabels = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
    private let weekdayLabelsFull = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัส", "ศุกร์", "เสาร์"]

    private static let tripOpsColor = Color(hex: "#2563EB")
    private static let sandOpsColor = Color(hex: "#DB2777")

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceXL) {
            heroCard
            calendarCard
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: visibleMonth)
        .onAppear { scheduleDaysRebuild(showSkeleton: days.isEmpty) }
        .onDisappear {
            buildTask?.cancel()
            buildTask = nil
        }
        .onChange(of: visibleMonth) { _, _ in
            scheduleDaysRebuild(showSkeleton: true)
        }
        .onChange(of: transactions.count) { _, _ in
            scheduleDaysRebuild(showSkeleton: false)
        }
        .onChange(of: employees.count) { _, _ in
            scheduleDaysRebuild(showSkeleton: false)
        }
        .sheet(item: selectedDayBinding) { day in
            DayDetailSheet(
                day: day,
                employees: employees,
                transactions: transactions,
                onClose: { selectedDay = nil }
            )
        }
    }

    private func scheduleDaysRebuild(showSkeleton: Bool) {
        buildTask?.cancel()
        let month = visibleMonth
        let txs = transactions
        let emps = employees
        if showSkeleton {
            days = CalendarV3Logic.skeletonDays(visibleMonth: month)
        }
        isBuildingDays = true
        buildTask = Task {
            let built = await Task.detached(priority: .userInitiated) {
                CalendarV3Logic.buildDays(
                    visibleMonth: month,
                    transactions: txs,
                    employees: emps
                )
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                days = built
                isBuildingDays = false
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(hex: "#042F36"),
                    AppTheme.brandDark,
                    AppTheme.brand
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 140, height: 140)
                .blur(radius: 24)
                .offset(x: 210, y: -40)

            VStack(alignment: .leading, spacing: 14) {
                Text(monthTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("แตะวันเพื่อดูสรุป · จุดฟ้า = เที่ยวรถ · จุดชมพู = ร่อนทราย")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                monthNavigation
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: AppTheme.brand.opacity(0.28), radius: 14, y: 6)
    }

    // MARK: - Month navigation

    private var monthNavigation: some View {
        HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: {
                navCircle("chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนก่อน")

            if !isCurrentMonth {
                Button { goThisMonth() } label: {
                    Text("เดือนนี้")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            Button { shiftMonth(1) } label: {
                navCircle("chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนถัดไป")
        }
    }

    private func navCircle(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.white.opacity(0.16)))
    }

    // MARK: - Calendar card

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ตารางเดือน")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                if isBuildingDays {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("กำลังโหลด…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    .accessibilityLabel("กำลังโหลดข้อมูลปฏิทิน")
                }
            }

            legendStrip
            calendarGrid
        }
        .padding(AppTheme.spaceLG)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var legendStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                legendChip(color: AppTheme.income, label: "รายรับ")
                legendChip(color: AppTheme.expense, label: "รายจ่าย")
                legendChip(color: AppTheme.purple, label: "นัดหมาย")
                legendChip(color: AppTheme.expense, label: "วันหยุด")
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                legendChip(color: Self.tripOpsColor, label: "เที่ยวรถ")
                legendChip(color: Self.sandOpsColor, label: "ร่อนทราย")
                Spacer(minLength: 0)
            }
        }
    }

    private func legendChip(color: Color, label: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
        }
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let leading = CalendarV3Logic.leadingBlankCount(visibleMonth: visibleMonth)
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, d in
                    Text(d)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == 0 ? AppTheme.expense.opacity(0.85) : AppTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)
                        .accessibilityLabel(weekdayLabelsFull[index])
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leading, id: \.self) { i in
                    Color.clear
                        .frame(minHeight: 68)
                        .id("blank-\(i)")
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

    private func dayCell(_ day: CalendarDayModel) -> some View {
        let isSelected = selectedDay == day.date
        let isToday = day.date == DashboardAggregations.todayYMD()
        let style = DayCellStyle(day: day)

        return Button {
            guard !isBuildingDays else { return }
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day.date }
            onDaySelected?(day.date)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 2) {
                    Text("\(day.day)")
                        .font(.system(size: 14, weight: isToday || isSelected ? .bold : .semibold))
                        .foregroundStyle(
                            isSelected
                                ? .white
                                : (isToday && !day.hasFinance ? AppTheme.brand : style.dayNumberColor)
                        )
                    Spacer(minLength: 0)
                    indicatorDots(day, onSelected: isSelected)
                }
                opsMarkDots(day.opsMark, onSelected: isSelected)
                    .frame(height: 6)
                Spacer(minLength: 0)
                if day.hasFinance {
                    Text(compactNet(day.net))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.95) : (day.net >= 0 ? AppTheme.income : AppTheme.expense))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppTheme.brand : style.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.clear
                            : (isToday ? AppTheme.brand.opacity(0.7) : style.border),
                        lineWidth: isToday && !isSelected ? 1.8 : (day.hasFinance || day.opsMark != .none ? 1 : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isBuildingDays)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func compactNet(_ net: Double) -> String {
        let prefix = net > 0 ? "+" : ""
        let abs = abs(net)
        if abs >= 1000 {
            return "\(prefix)\(DashboardAggregations.formatNumber(abs / 1000))k"
        }
        return "\(prefix)\(DashboardAggregations.formatNumber(abs))"
    }

    private func indicatorDots(_ day: CalendarDayModel, onSelected: Bool) -> some View {
        HStack(spacing: 2) {
            if day.hasHoliday { microDot(onSelected ? .white : AppTheme.expense) }
            if day.hasAppointment { microDot(onSelected ? .white.opacity(0.85) : AppTheme.purple) }
            if day.hasReminder { microDot(onSelected ? .white.opacity(0.7) : AppTheme.warning) }
            if day.presentCount > 0 { microDot(onSelected ? .white.opacity(0.7) : AppTheme.info) }
        }
        .frame(height: 5)
    }

    private func opsMarkDots(_ mark: CountRecordLogic.DayOpsMark, onSelected: Bool) -> some View {
        HStack(spacing: 3) {
            switch mark {
            case .none:
                Color.clear.frame(width: 5, height: 5)
            case .tripOnly:
                microDot(onSelected ? .white : Self.tripOpsColor, size: 5)
            case .sandOnly:
                microDot(onSelected ? .white : Self.sandOpsColor, size: 5)
            case .both:
                microDot(onSelected ? .white : Self.tripOpsColor, size: 5)
                microDot(onSelected ? .white.opacity(0.85) : Self.sandOpsColor, size: 5)
            }
        }
    }

    private func microDot(_ color: Color, size: CGFloat = 4) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }

    private func accessibilityLabel(_ day: CalendarDayModel) -> String {
        var parts = ["วันที่ \(day.day)"]
        if day.income > 0 { parts.append("รายรับ \(DashboardAggregations.formatNumber(day.income))") }
        if day.expense > 0 { parts.append("รายจ่าย \(DashboardAggregations.formatNumber(day.expense))") }
        if day.hasHoliday { parts.append("วันหยุด") }
        if day.hasAppointment { parts.append("มีนัดหมาย") }
        if day.presentCount > 0 { parts.append("มาทำงาน \(day.presentCount)") }
        if day.leaveCount > 0 { parts.append("ลา \(day.leaveCount)") }
        switch day.opsMark {
        case .none: break
        case .tripOnly: parts.append("มีเที่ยวรถ")
        case .sandOnly: parts.append("มีร่อนทราย")
        case .both: parts.append("มีเที่ยวรถและร่อนทราย")
        }
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

    private var isCurrentMonth: Bool {
        let cal = DashboardAggregations.gregorian
        let now = Date()
        return cal.component(.year, from: visibleMonth) == cal.component(.year, from: now)
            && cal.component(.month, from: visibleMonth) == cal.component(.month, from: now)
    }

    private func shiftMonth(_ delta: Int) {
        let next = DashboardAggregations.gregorian.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            visibleMonth = next
            selectedDay = nil
        }
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            visibleMonth = cal.date(from: comps) ?? Date()
            selectedDay = nil
        }
    }
}

// MARK: - Day cell styling

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
            background = Color.clear
            border = Color.clear
            dayNumberColor = AppTheme.inkSecondary
        }
    }
}

// MARK: - Ledger category buckets

private struct LedgerCategoryBucket: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let accent: Color
    let transactions: [Transaction]

    var expenseTotal: Double {
        transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var incomeTotal: Double {
        transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    /// Income positive, expense negative for signed display preference.
    var signedTotal: Double { incomeTotal - expenseTotal }

    var displayTotal: String {
        if incomeTotal > 0, expenseTotal == 0 {
            return DashboardAggregations.formatCurrency(incomeTotal)
        }
        if expenseTotal > 0, incomeTotal == 0 {
            return DashboardAggregations.formatCurrency(expenseTotal)
        }
        if incomeTotal > 0, expenseTotal > 0 {
            return "+\(DashboardAggregations.formatNumber(incomeTotal)) / -\(DashboardAggregations.formatNumber(expenseTotal))"
        }
        return "—"
    }

    static func group(_ txs: [Transaction]) -> [LedgerCategoryBucket] {
        let order: [(String, String, String, Color, (Transaction) -> Bool)] = [
            ("labor", "ค่าแรง", "person.2.fill", AppTheme.labor, { $0.category == "Labor" && !CalendarV3Logic.isLaborLeaveRecord($0) }),
            ("leave", "ลางาน", "calendar.badge.minus", AppTheme.warning, { CalendarV3Logic.isLaborLeaveRecord($0) || $0.category == "Leave" }),
            ("vehicle", "การใช้รถ", "truck.box.fill", AppTheme.vehicle, {
                $0.category == "Vehicle" || ($0.category == "DailyLog" && $0.subCategory == "VehicleTrip")
            }),
            ("sand", "ล้างทราย", "drop.fill", AppTheme.sand, {
                $0.category == "DailyLog" && $0.subCategory == "Sand"
            }),
            ("fuel", "น้ำมัน", "fuelpump.fill", AppTheme.fuel, { $0.category == "Fuel" }),
            ("land", "ที่ดิน", "map.fill", AppTheme.land, { $0.category == "Land" }),
            ("income", "รายรับ", "banknote.fill", AppTheme.income, { $0.type == .income }),
            ("machine", "เครื่องจักร", "gearshape.2.fill", AppTheme.slate, {
                $0.category == "DailyLog" && $0.subCategory == "MachineWork"
            }),
            ("other", "อื่นๆ", "ellipsis.circle.fill", AppTheme.slate, { _ in true })
        ]

        var claimed = Set<String>()
        var buckets: [LedgerCategoryBucket] = []
        for (id, title, icon, accent, predicate) in order {
            let rows: [Transaction]
            if id == "other" {
                rows = txs.filter { !claimed.contains($0.id) }
            } else if id == "income" {
                rows = txs.filter { predicate($0) && !claimed.contains($0.id) }
            } else {
                rows = txs.filter { predicate($0) && $0.type != .income && !claimed.contains($0.id) }
            }
            guard !rows.isEmpty else { continue }
            rows.forEach { claimed.insert($0.id) }
            buckets.append(
                LedgerCategoryBucket(
                    id: id,
                    title: title,
                    systemImage: icon,
                    accent: accent,
                    transactions: rows.sorted { $0.amount > $1.amount }
                )
            )
        }
        return buckets
    }
}

// MARK: - Selected-day detail sheet

private struct DayDetailSheet: View {
    let day: CalendarDayModel
    let employees: [Employee]
    let transactions: [Transaction]
    let onClose: () -> Void

    private static let tripOpsColor = Color(hex: "#2563EB")
    private static let sandOpsColor = Color(hex: "#DB2777")

    private var ledgerBuckets: [LedgerCategoryBucket] {
        LedgerCategoryBucket.group(financeTransactions)
    }

    private var dayTransactions: [Transaction] {
        transactions.filter { String($0.date.prefix(10)) == day.date }
    }

    private var financeTransactions: [Transaction] {
        if !day.financeTransactions.isEmpty { return day.financeTransactions }
        return dayTransactions.filter { !CalendarV3Logic.isCalendarTx($0) }
    }

    private var machineLogs: [Transaction] {
        if !day.machineLogs.isEmpty { return day.machineLogs }
        return financeTransactions.filter {
            $0.category == "DailyLog" && ($0.subCategory == "MachineWork" || $0.subCategory == "VehicleTrip")
        }
    }

    private var sandLogs: [Transaction] {
        if !day.sandLogs.isEmpty { return day.sandLogs }
        return financeTransactions.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
    }

    private var eventLogs: [Transaction] {
        if !day.eventLogs.isEmpty { return day.eventLogs }
        return financeTransactions.filter { $0.category == "DailyLog" && $0.subCategory == "Event" }
    }

    private var tripUnits: [CountRecordTripUnit] {
        CountRecordLogic.buildTripUnits(
            dayKey: day.date,
            transactions: dayTransactions,
            employees: employees
        )
    }

    private var sandUnit: CountRecordSandUnit? {
        CountRecordLogic.buildSandUnit(dayKey: day.date, transactions: dayTransactions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                    header
                    if day.opsMark != .none { realtimeOpsSection }
                    financeDashboard
                    if !day.calendarRows.isEmpty { calendarSection }
                    attendanceSection
                    if hasOpsActivity { opsActivitySection }
                    ledgerDashboard
                }
                .padding(AppTheme.spaceLG)
                .padding(.bottom, AppTheme.spaceXL)
            }
            .background(DashboardBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("รายละเอียดวัน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { onClose() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var hasOpsActivity: Bool {
        !machineLogs.isEmpty || !sandLogs.isEmpty || !eventLogs.isEmpty
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(longThaiDate(day.date))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(financeTransactions.count) รายการเดินบัญชี · \(ledgerBuckets.count) หมวด")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.24), radius: 12, y: 5)
    }

    // MARK: Realtime ops summary

    private var realtimeOpsSection: some View {
        let trips = tripUnits
        let tripTotal = trips.reduce(0) { $0 + $1.rounds }
        let tripMorning = trips.reduce(0) { $0 + $1.morning }
        let tripAfternoon = trips.reduce(0) { $0 + $1.afternoon }
        let sand = sandUnit

        return SectionCard("ปฏิบัติการวันนี้", systemImage: "wrench.and.screwdriver.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if day.hasTripOps, tripTotal > 0 {
                    opsSummaryCard(
                        title: "เที่ยวรถ",
                        icon: "truck.box.fill",
                        tint: Self.tripOpsColor,
                        primary: "\(trips.count) คัน · \(CountRecordLogic.formatMetric(tripTotal)) เที่ยว",
                        secondary: "เช้า \(tripMorning) · บ่าย \(tripAfternoon)"
                    )
                }
                if day.hasSandOps, let sand, sand.rounds > 0 {
                    opsSummaryCard(
                        title: "ร่อนทราย",
                        icon: "drop.fill",
                        tint: Self.sandOpsColor,
                        primary: "\(CountRecordLogic.formatMetric(sand.rounds)) รอบ",
                        secondary: "เช้า \(sand.morning) · บ่าย \(sand.afternoon)"
                    )
                }
            }
        }
    }

    private func opsSummaryCard(
        title: String,
        icon: String,
        tint: Color,
        primary: String,
        secondary: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(primary)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(secondary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: Finance KPIs

    private var financeDashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("สรุปการเงินวันนี้")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 10) {
                dayKPI(title: "รายรับ", value: DashboardAggregations.formatCurrency(day.income), tint: AppTheme.income)
                dayKPI(title: "รายจ่าย", value: DashboardAggregations.formatCurrency(day.expense), tint: AppTheme.expense)
                dayKPI(
                    title: "สุทธิ",
                    value: (day.net >= 0 ? "+" : "") + DashboardAggregations.formatCurrency(day.net),
                    tint: day.net >= 0 ? AppTheme.brand : AppTheme.warning
                )
            }

            if !ledgerBuckets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ledgerBuckets) { bucket in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(bucket.title, systemImage: bucket.systemImage)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(bucket.accent)
                                    .lineLimit(1)
                                Text(bucket.displayTotal)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("\(bucket.transactions.count) รายการ")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(10)
                            .frame(minWidth: 108, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(bucket.accent.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(bucket.accent.opacity(0.22), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private func dayKPI(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: Calendar events

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
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.surfaceSoft)
                    )
                }
            }
        }
    }

    // MARK: Attendance

    private var attendanceSection: some View {
        SectionCard(
            "การมาทำงาน",
            systemImage: "person.2.fill",
            subtitle: "เฉพาะพนักงานท่าทราย + คนขับรถแม็คโคร"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                attendanceTile(count: day.presentCount, title: "มา", color: AppTheme.income)
                attendanceTile(count: day.leaveCount, title: "ลา", color: AppTheme.warning)
                attendanceTile(count: day.missingCount, title: "ขาด", color: AppTheme.expense)
            }
            if !day.leaveNames.isEmpty {
                Text("ลา: \(day.leaveNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }

    private func attendanceTile(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: Ops activity

    private var opsActivitySection: some View {
        SectionCard("บันทึกปฏิบัติการ", systemImage: "gearshape.2.fill") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(machineLogs) { t in
                    activityRow(systemImage: "gearshape.2.fill", tint: AppTheme.vehicle, text: machineText(t))
                }
                ForEach(sandLogs) { t in
                    activityRow(systemImage: "drop.fill", tint: AppTheme.dailyLog, text: sandText(t))
                }
                ForEach(eventLogs) { t in
                    activityRow(systemImage: "pin.fill", tint: AppTheme.warning, text: t.description)
                }
            }
        }
    }

    private func activityRow(systemImage: String, tint: Color, text: String) -> some View {
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }

    // MARK: Ledger by category

    private var ledgerDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("รายการเดินบัญชี", systemImage: "list.bullet.rectangle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                Text("แยกตามหมวด")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.brand.opacity(0.12)))
            }

            if ledgerBuckets.isEmpty {
                EmptyStateView(title: "ไม่มีรายการเดินบัญชี", systemImage: "tray")
                    .padding(.vertical, 8)
            } else {
                ForEach(ledgerBuckets) { bucket in
                    categoryLedgerCard(bucket)
                }
            }
        }
        .padding(AppTheme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 14, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func categoryLedgerCard(_ bucket: LedgerCategoryBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: bucket.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(bucket.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(bucket.accent.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("\(bucket.transactions.count) รายการ")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Text(bucket.displayTotal)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(bucket.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            VStack(spacing: 6) {
                ForEach(bucket.transactions) { t in
                    ledgerRow(t, accent: bucket.accent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surfaceSoft.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(bucket.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private func ledgerRow(_ t: Transaction, accent: Color) -> some View {
        let isIncome = t.type == .income
        let amountColor: Color = isIncome ? AppTheme.income : (CalendarV3Logic.isLaborLeaveRecord(t) ? AppTheme.warning : AppTheme.expense)
        let amountText: String = t.amount > 0
            ? "฿" + DashboardAggregations.formatNumber(t.amount)
            : (CalendarV3Logic.isLaborLeaveRecord(t) || t.category == "Leave" ? "ลา" : "—")

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.description.isEmpty ? (t.subCategory ?? t.category) : t.description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                if let sub = t.subCategory, !sub.isEmpty, sub != t.description {
                    Text(sub)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(amountText)
                .font(.caption.weight(.bold))
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

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
