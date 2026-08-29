import SwiftUI

/// Read-only daily work log ("บันทึกงาน") — mirrors the web recorder's daily journal
/// on the read-only iOS client: pick a day, review everything recorded for it.
struct WorkLogView: View {
    let transactions: [Transaction]
    let employees: [Employee]
    let settings: AppSettings

    @State private var selectedDate = Date()
    @State private var showDatePicker = false

    private var dayKey: String { DashboardAggregations.formatYMD(selectedDate) }
    private var todayKey: String { DashboardAggregations.formatYMD(Date()) }
    private var isToday: Bool { dayKey == todayKey }

    private var dayTransactions: [Transaction] {
        transactions
            .filter { String($0.date.prefix(10)) == dayKey }
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }

    private var income: Double {
        dayTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + displayMonetaryAmount($1) }
    }
    private var expense: Double {
        dayTransactions
            .filter { $0.type == .expense && $0.category != "Fuel" }
            .reduce(0) { $0 + displayMonetaryAmount($1) }
    }

    private var tripUnits: [CountRecordTripUnit] {
        CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: transactions,
            employees: employees,
            cars: settings.cars,
            catalog: settings.vehicleCatalog
        )
    }
    private var sandUnit: CountRecordSandUnit? {
        CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: transactions)
    }
    private var tripTotal: Int { tripUnits.reduce(0) { $0 + $1.rounds } }

    /// Categories in a friendly order, each with its records for the day.
    private var groupedRecords: [(category: String, items: [Transaction])] {
        let order = ["Income", "Labor", "Vehicle", "Sand", "Fuel", "Maintenance", "Land", "DailyLog"]
        let grouped = Dictionary(grouping: dayTransactions) { $0.category.isEmpty ? "อื่น ๆ" : $0.category }
        return grouped
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                let li = order.firstIndex(of: lhs.0) ?? order.count
                let ri = order.firstIndex(of: rhs.0) ?? order.count
                if li != ri { return li < ri }
                return lhs.0 < rhs.0
            }
    }

    var body: some View {
        VStack(spacing: AppTheme.spaceLG) {
            heroHeader
            if dayTransactions.isEmpty {
                SectionCard {
                    EmptyStateView(
                        title: "ยังไม่มีบันทึกงานวันนี้",
                        message: "เลือกวันอื่นหรือรอการบันทึกจากแอปมือถือ",
                        systemImage: "square.and.pencil"
                    )
                }
            } else {
                if !tripUnits.isEmpty || sandUnit != nil {
                    countRecordSummary
                }
                ForEach(groupedRecords, id: \.category) { group in
                    categorySection(category: group.category, items: group.items)
                }
            }
        }
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        Button {
            showDatePicker = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("บันทึกงานประจำวัน")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(DashboardAggregations.thaiDateLong(dayKey))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                }

                HStack(spacing: 10) {
                    heroStat(title: "รายรับ", value: DashboardAggregations.formatCurrency(income), tint: Color(hex: "#A7F3D0"))
                    heroStat(title: "รายจ่าย", value: DashboardAggregations.formatCurrency(expense), tint: Color(hex: "#FECACA"))
                    heroStat(title: "รายการ", value: "\(dayTransactions.count)", tint: .white)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 140, height: 140)
                        .blur(radius: 24)
                        .offset(x: 40, y: -40)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: AppTheme.brand.opacity(0.35), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func heroStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.subheadline.weight(.black))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
    }

    // MARK: - Count record summary

    private var countRecordSummary: some View {
        SectionCard("สรุปการนับงาน", systemImage: "gauge.with.dots.needle.67percent") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                if !tripUnits.isEmpty {
                    KPITile(
                        title: "เที่ยวรถ",
                        value: "\(CountRecordLogic.formatMetric(tripTotal)) เที่ยว",
                        subtitle: "\(tripUnits.count) คัน",
                        accent: AppTheme.info,
                        systemImage: "truck.box.fill"
                    )
                }
                if let sand = sandUnit {
                    KPITile(
                        title: "ร่อนทราย",
                        value: "\(CountRecordLogic.formatMetric(sand.rounds)) รอบ",
                        subtitle: "เช้า \(sand.morning) · บ่าย \(max(0, sand.afternoon - sand.ot))",
                        accent: AppTheme.sand,
                        systemImage: "drop.fill"
                    )
                }
            }
            if !tripUnits.isEmpty {
                VStack(spacing: 8) {
                    ForEach(tripUnits) { unit in
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                                .foregroundStyle(AppTheme.info)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(unit.vehicleId).font(.subheadline.weight(.semibold))
                                Text(unit.driverLabel).font(.caption).foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer()
                            Text("\(unit.rounds) เที่ยว")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.info)
                        }
                        .padding(.vertical, 6)
                        if unit.id != tripUnits.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Category sections

    private func categorySection(category: String, items: [Transaction]) -> some View {
        return SectionCard(categoryLabel(category), systemImage: categoryIcon(category)) {
            VStack(spacing: 8) {
                ForEach(items) { tx in
                    recordRow(tx)
                    if tx.id != items.last?.id { Divider() }
                }
            }
            categoryFooter(category: category, items: items)
        }
    }

    @ViewBuilder
    private func categoryFooter(category: String, items: [Transaction]) -> some View {
        if category == "Fuel" {
            let liters = items.reduce(0.0) { $0 + FuelLogic.liters(of: $1) }
            if liters != 0 {
                HStack {
                    Text("รวมปริมาณ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    Spacer()
                    Text("\(FuelLogic.formatLiters(liters)) L")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.fuel)
                }
                .padding(.top, 4)
            }
        } else {
            let total = items.reduce(0.0) { acc, tx in
                let amt = displayMonetaryAmount(tx)
                switch tx.type {
                case .income: return acc + amt
                case .expense: return acc - amt
                case .leave: return acc
                }
            }
            if total != 0 {
                HStack {
                    Text("สุทธิหมวดนี้")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    Spacer()
                    Text(DashboardAggregations.formatCurrency(total))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(total >= 0 ? AppTheme.income : AppTheme.expense)
                }
                .padding(.top, 4)
            }
        }
    }

    /// Labor/Vehicle often persist `amount = 0` and store wages elsewhere — mirror web wizard totals.
    private func displayMonetaryAmount(_ tx: Transaction) -> Double {
        if tx.category == "Labor" {
            let ids = (tx.employeeIds ?? []).filter { !$0.isEmpty }
            if !ids.isEmpty {
                let wageSum = ids.reduce(0.0) {
                    $0 + DashboardAggregations.laborWageForEmployee(tx, employeeId: $1, employees: employees)
                }
                if wageSum > 0 { return wageSum }
            }
        }
        let inferred = DashboardAggregations.wizardMonetaryAmount(tx, employees: employees)
        if inferred > 0 { return inferred }
        return tx.amount
    }

    private func recordRow(_ tx: Transaction) -> some View {
        let amountColor: Color = {
            if tx.category == "Fuel" { return AppTheme.fuel }
            switch tx.type {
            case .income: return AppTheme.income
            case .expense: return AppTheme.expense
            case .leave: return AppTheme.slate
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tx.description.isEmpty ? (tx.subCategory ?? "—") : tx.description)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                if tx.type == .leave {
                    PillBadge(text: "ลา", color: AppTheme.slate)
                } else if tx.category == "Fuel" {
                    Text("\(FuelLogic.formatLiters(FuelLogic.liters(of: tx))) L")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(amountColor)
                } else {
                    Text(DashboardAggregations.formatCurrency(displayMonetaryAmount(tx)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(amountColor)
                }
            }
            HStack(spacing: 6) {
                if let sub = tx.subCategory, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundStyle(AppTheme.inkMuted)
                }
                if let time = eventTimeLabel(tx) {
                    Label(time, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                if let note = tx.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(AppTheme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func eventTimeLabel(_ tx: Transaction) -> String? {
        if let t = tx.eventTime, !t.isEmpty { return t }
        if let created = tx.createdAt, created.count >= 16 {
            return String(created.dropFirst(11).prefix(5))
        }
        return nil
    }

    // MARK: - Category naming

    private func categoryLabel(_ key: String) -> String {
        switch key {
        case "Income": return "รายรับ"
        case "Labor": return "ค่าแรง"
        case "Vehicle": return "การใช้รถ"
        case "Sand": return "ล้างทราย"
        case "Fuel": return "น้ำมัน"
        case "Maintenance": return "ซ่อมบำรุง"
        case "Land": return "ที่ดิน"
        case "DailyLog": return "บันทึกประจำวัน"
        default: return key
        }
    }

    private func categoryIcon(_ key: String) -> String {
        switch key {
        case "Income": return "banknote.fill"
        case "Labor": return "person.2.fill"
        case "Vehicle": return "truck.box.fill"
        case "Sand": return "drop.fill"
        case "Fuel": return "fuelpump.fill"
        case "Maintenance": return "wrench.and.screwdriver.fill"
        case "Land": return "map.fill"
        case "DailyLog": return "note.text"
        default: return "square.grid.2x2.fill"
        }
    }

    // MARK: - Date sheet

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "เลือกวันที่",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(AppTheme.brand)
                .padding(.horizontal, 8)

                Button {
                    selectedDate = Date()
                } label: {
                    Label("วันนี้", systemImage: "sun.max.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.brand)
                .padding(.horizontal, 20)
                .disabled(isToday)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("เลือกวันบันทึกงาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ") { showDatePicker = false }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
