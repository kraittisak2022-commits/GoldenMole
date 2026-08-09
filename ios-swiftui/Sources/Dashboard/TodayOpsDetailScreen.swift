import SwiftUI

/// Home «งานจากแอพ · วันนี้» card destinations — read-only today detail per ops kind.
enum TodayOpsDetailKind: String, CaseIterable, Identifiable, Sendable {
    case trips
    case sand
    case attendance
    case macro
    case fuelStockIn
    case fuelWithdraw
    case fuelCarFill
    case fuelMacroUsage
    case leave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: return "เที่ยวรถ"
        case .sand: return "ร่อนทราย"
        case .attendance: return "เช็คชื่อ"
        case .macro: return "แม็คโคร"
        case .fuelStockIn: return "เพิ่มน้ำมัน"
        case .fuelWithdraw: return "เบิกน้ำมัน"
        case .fuelCarFill: return "เติมน้ำมันรถยนต์"
        case .fuelMacroUsage: return "การใช้น้ำมันรถแม็คโคร"
        case .leave: return "ลางาน"
        }
    }

    var systemImage: String {
        switch self {
        case .trips: return "truck.box.fill"
        case .sand: return "drop.fill"
        case .attendance: return "person.3.fill"
        case .macro: return "hammer.fill"
        case .fuelStockIn: return "arrow.down.to.line.circle.fill"
        case .fuelWithdraw: return "arrow.up.right.circle.fill"
        case .fuelCarFill: return "car.fill"
        case .fuelMacroUsage: return "fuelpump.fill"
        case .leave: return "calendar.badge.minus"
        }
    }

    var accent: Color {
        switch self {
        case .trips: return AppTheme.vehicle
        case .sand: return AppTheme.sand
        case .attendance: return AppTheme.labor
        case .macro: return Color(hex: "#0F766E")
        case .fuelStockIn, .fuelWithdraw, .fuelCarFill, .fuelMacroUsage: return AppTheme.fuel
        case .leave: return AppTheme.warning
        }
    }
}

struct TodayOpsDetailScreen: View {
    let kind: TodayOpsDetailKind

    @Environment(AppState.self) private var appState
    @State private var mobile = MobileOpsMetrics.empty
    @State private var todayOps = TodayOpsSnapshot.empty
    @State private var tripUnits: [CountRecordTripUnit] = []
    @State private var sandUnit: CountRecordSandUnit?
    @State private var sandRows: [Transaction] = []
    @State private var macroRows: [Transaction] = []
    @State private var fuelRows: [Transaction] = []

    private var dayKey: String { DashboardAggregations.todayYMD() }

    var body: some View {
        Group {
            if kind == .attendance {
                OpsAttendanceDetailView()
            } else {
                detailScroll
            }
        }
        .background(DashboardBackground())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    recordDestination
                } label: {
                    Text("บันทึก")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .task(id: "\(kind.rawValue)-\(dayKey)-\(appState.transactionsRevision)") {
            await reload()
        }
    }

    // MARK: - Record hubs

    @ViewBuilder
    private var recordDestination: some View {
        switch kind {
        case .trips, .sand:
            CountRecordHubView()
        case .attendance:
            AttendanceHubView()
        case .macro:
            MacroVehicleHubView()
        case .fuelStockIn:
            FuelHubView(initialSubMode: .stockIn)
        case .fuelWithdraw:
            FuelHubView(initialSubMode: .withdraw)
        case .fuelCarFill:
            FuelHubView(initialSubMode: .carFill)
        case .fuelMacroUsage:
            FuelHubView(initialSubMode: .macroUsage)
        case .leave:
            LeaveHubView()
        }
    }

    // MARK: - Content

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                listContent
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollContentBackground(.hidden)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(kind.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(DashboardAggregations.thaiDateLong(dayKey))
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(heroStats, id: \.title) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stat.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                        Text(stat.value)
                            .font(.title3.weight(.black))
                            .foregroundStyle(kind.accent)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(kind.accent.opacity(0.1))
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(kind.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var heroStats: [(title: String, value: String)] {
        switch kind {
        case .trips:
            return [
                ("เที่ยว", "\(mobile.tripRounds)"),
                ("คัน", "\(mobile.tripVehicles)"),
                ("คิว", DashboardAggregations.formatNumber(mobile.tripCubic)),
                ("เช้า / บ่าย", "\(mobile.tripMorning) / \(mobile.tripAfternoon)"),
            ]
        case .sand:
            return [
                ("รอบ", "\(mobile.sandRounds)"),
                ("คิวล้าง", DashboardAggregations.formatNumber(mobile.sandWashedCubic)),
                ("ถังได้", DashboardAggregations.formatNumber(mobile.drumsObtained)),
                ("ถังบ้าน", DashboardAggregations.formatNumber(mobile.drumsHome)),
            ]
        case .attendance:
            return []
        case .macro:
            return [
                ("ครั้ง", "\(mobile.macroUsageCount)"),
                ("คัน", "\(mobile.macroVehicles)"),
            ]
        case .fuelStockIn:
            return [
                ("เข้าวันนี้", "\(DashboardAggregations.formatNumber(mobile.fuelInLiters)) L"),
                ("ถังหลัก", "\(DashboardAggregations.formatNumber(todayOps.mainDieselLiters)) L"),
                ("ถังสำรอง", "\(DashboardAggregations.formatNumber(todayOps.reserveDieselLiters)) L"),
            ]
        case .fuelWithdraw:
            return [
                ("เบิกวันนี้", "\(DashboardAggregations.formatNumber(mobile.fuelWithdrawLiters)) L"),
                ("ครั้ง", "\(mobile.fuelWithdrawCount)"),
                ("ถังหลัก", "\(DashboardAggregations.formatNumber(todayOps.mainDieselLiters)) L"),
                ("ถังสำรอง", "\(DashboardAggregations.formatNumber(todayOps.reserveDieselLiters)) L"),
            ]
        case .fuelCarFill:
            return [
                ("เติมวันนี้", "\(DashboardAggregations.formatNumber(mobile.fuelCarFillLiters)) L"),
                ("ครั้ง", "\(mobile.fuelCarFillCount)"),
                ("ถังหลัก", "\(DashboardAggregations.formatNumber(todayOps.mainDieselLiters)) L"),
                ("ถังสำรอง", "\(DashboardAggregations.formatNumber(todayOps.reserveDieselLiters)) L"),
            ]
        case .fuelMacroUsage:
            return [
                ("ใช้วันนี้", "\(DashboardAggregations.formatNumber(mobile.fuelMacroUsageLiters)) L"),
                ("คัน", "\(mobile.fuelMacroVehicles)"),
                ("ถังหลัก", "\(DashboardAggregations.formatNumber(todayOps.mainDieselLiters)) L"),
                ("ถังสำรอง", "\(DashboardAggregations.formatNumber(todayOps.reserveDieselLiters)) L"),
            ]
        case .leave:
            return [
                ("ลา", "\(todayOps.leaveCount)"),
                ("มาทำงาน", "\(todayOps.presentCount)"),
                ("ขาด", "\(todayOps.absentCount)"),
            ]
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch kind {
        case .trips:
            tripList
        case .sand:
            sandList
        case .attendance:
            EmptyView()
        case .macro:
            macroList
        case .fuelStockIn, .fuelWithdraw, .fuelCarFill, .fuelMacroUsage:
            fuelList
        case .leave:
            leaveList
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private var tripList: some View {
        let active = tripUnits.filter { $0.rounds > 0 }.sorted { $0.rounds > $1.rounds }
        if active.isEmpty {
            emptyCard(
                title: "ยังไม่มีเที่ยวรถวันนี้",
                message: "เมื่อมีการนับเที่ยวจากแอป จะแสดงรายคันที่นี่"
            )
        } else {
            SectionCard("รายคัน · \(active.count)", systemImage: kind.systemImage) {
                VStack(spacing: 0) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, unit in
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                                .foregroundStyle(kind.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.vehicleId)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(unit.driverLabel.isEmpty ? "—" : unit.driverLabel)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                                Text("เช้า \(unit.morning) · บ่าย \(max(0, unit.afternoon - unit.ot))\(unit.ot > 0 ? " · OT \(unit.ot)" : "")")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer()
                            Text("\(unit.rounds)")
                                .font(.title3.weight(.black))
                                .foregroundStyle(kind.accent)
                            Text("เที่ยว")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        .padding(.vertical, 10)
                        if index < active.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sandList: some View {
        if sandUnit == nil && sandRows.isEmpty {
            emptyCard(
                title: "ยังไม่มีร่อนทรายวันนี้",
                message: "เมื่อมีการนับรอบร่อนทราย จะแสดงรายละเอียดที่นี่"
            )
        } else {
            SectionCard("รอบวันนี้", systemImage: kind.systemImage) {
                VStack(alignment: .leading, spacing: 12) {
                    if let sand = sandUnit {
                        HStack {
                            Text("รวม \(sand.rounds) รอบ")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text("เช้า \(sand.morning) · บ่าย \(max(0, sand.afternoon - sand.ot))")
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        if !sand.lapTimes.isEmpty {
                            Text("เวลาแลปล่าสุด")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.inkMuted)
                            ForEach(Array(sand.lapTimes.suffix(12).reversed().enumerated()), id: \.offset) { _, lap in
                                Text(lap)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                    ForEach(sandRows) { row in
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.description.isEmpty ? "ร่อนทราย" : row.description)
                                    .font(.subheadline.weight(.semibold))
                                Text("ล้าง \(DashboardAggregations.formatNumber(DashboardAggregations.sandWashedCubic(row))) คิว")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer()
                            if let drums = row.drumsObtained {
                                Text("\(DashboardAggregations.formatNumber(drums)) ถัง")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(kind.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var macroList: some View {
        if macroRows.isEmpty {
            emptyCard(
                title: "ยังไม่มีใช้รถแม็คโครวันนี้",
                message: "เมื่อมีการบันทึกการใช้แม็คโคร จะแสดงที่นี่"
            )
        } else {
            SectionCard("รายการ · \(macroRows.count)", systemImage: kind.systemImage) {
                VStack(spacing: 0) {
                    ForEach(Array(macroRows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(kind.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "แม็คโคร")
                                    .font(.subheadline.weight(.semibold))
                                Text(macroSubtitle(row))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer()
                            if row.amount > 0 {
                                Text(DashboardAggregations.formatCurrency(row.amount))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.inkSecondary)
                            }
                        }
                        .padding(.vertical, 10)
                        if index < macroRows.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fuelList: some View {
        if fuelRows.isEmpty {
            emptyCard(
                title: "ยังไม่มี\(kind.title)วันนี้",
                message: "เมื่อมีการบันทึก จะแสดงรายการลิตรที่นี่"
            )
        } else {
            let total = fuelRows.reduce(0.0) { $0 + DashboardAggregations.fuelTxToLiters($1) }
            SectionCard(
                "รายการ · \(fuelRows.count)",
                systemImage: kind.systemImage,
                subtitle: "รวม \(DashboardAggregations.formatNumber(total)) L"
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(fuelRows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(kind.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fuelTitle(row))
                                    .font(.subheadline.weight(.semibold))
                                Text(fuelSubtitle(row))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer()
                            Text("\(DashboardAggregations.formatNumber(DashboardAggregations.fuelTxToLiters(row))) L")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(kind.accent)
                        }
                        .padding(.vertical, 10)
                        if index < fuelRows.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var leaveList: some View {
        let rows = todayOps.staffRows.filter { $0.status == .leave }
        if rows.isEmpty {
            emptyCard(
                title: "ยังไม่มีพนักงานลาวันนี้",
                message: "เมื่อมีบันทึกลาในพูลท่าทราย/คนขับแม็คโคร จะแสดงที่นี่"
            )
        } else {
            SectionCard("รายชื่อลา · \(rows.count)", systemImage: kind.systemImage) {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(kind.accent.opacity(0.25))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.subheadline.weight(.semibold))
                                if !row.workLabels.isEmpty {
                                    Text(row.workLabels.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkMuted)
                                }
                            }
                            Spacer()
                            if row.wage > 0 {
                                Text(DashboardAggregations.formatCurrency(row.wage))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.inkSecondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.surfaceSoft)
                        )
                    }
                }
            }
        }
    }

    private func emptyCard(title: String, message: String) -> some View {
        SectionCard {
            EmptyStateView(
                title: title,
                message: message,
                systemImage: kind.systemImage
            )
        }
    }

    // MARK: - Helpers

    private func macroSubtitle(_ t: Transaction) -> String {
        var parts: [String] = []
        parts.append(MacroVehicleLogic.WorkType.from(raw: t.workType).label)
        let details = MacroVehicleLogic.stripRecorderSuffix(t.workDetails ?? "")
        let tags = MacroVehicleLogic.parseWorkTags(details)
        if !tags.isEmpty {
            parts.append(contentsOf: tags)
        } else if !details.isEmpty {
            parts.append(details)
        }
        return parts.joined(separator: " · ")
    }

    private func fuelTitle(_ t: Transaction) -> String {
        switch kind {
        case .fuelStockIn:
            return t.fuelType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? (t.description.isEmpty ? "รับเข้า" : t.description)
        case .fuelWithdraw:
            return t.subCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? (t.description.isEmpty ? "เบิกน้ำมัน" : t.description)
        case .fuelCarFill:
            return t.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? (t.description.isEmpty ? "เติมน้ำมันรถยนต์" : t.description)
        case .fuelMacroUsage:
            return t.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "รถแม็คโคร"
        default:
            return t.description.isEmpty ? kind.title : t.description
        }
    }

    private func fuelSubtitle(_ t: Transaction) -> String {
        var parts: [String] = []
        if let ft = t.fuelType, !ft.isEmpty { parts.append(ft) }
        let desc = t.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty, desc != fuelTitle(t) { parts.append(desc) }
        if let time = t.createdAt?.prefix(16), !time.isEmpty {
            parts.append(String(time).replacingOccurrences(of: "T", with: " "))
        }
        return parts.isEmpty ? "วันนี้" : parts.joined(separator: " · ")
    }

    private func reload() async {
        let txs = appState.transactions
        let emps = appState.employees
        let settings = appState.settings
        let key = dayKey
        let kind = self.kind

        let bundle = await Task.detached(priority: .userInitiated) { () -> (
            MobileOpsMetrics,
            TodayOpsSnapshot,
            [CountRecordTripUnit],
            CountRecordSandUnit?,
            [Transaction],
            [Transaction],
            [Transaction]
        ) in
            let mobile = MobileOpsSnapshot.metricsForDay(
                dayKey: key,
                transactions: txs,
                employees: emps
            )
            let ops = TodayOpsSnapshot.build(
                transactions: txs,
                employees: emps,
                settings: settings,
                dayKey: key
            )
            let trips = CountRecordLogic.buildTripUnits(
                dayKey: key,
                transactions: txs,
                employees: emps
            )
            let sand = CountRecordLogic.buildSandUnit(dayKey: key, transactions: txs)
            let dayTx = txs.filter { String($0.date.prefix(10)) == key }
            let sandRows = dayTx
                .filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            let macro = dayTx
                .filter { DashboardAggregations.isMacroUsageRow($0) }
                .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            let fuel: [Transaction]
            switch kind {
            case .fuelStockIn:
                fuel = dayTx.filter { FuelLogic.isStockIn($0) }
            case .fuelWithdraw:
                fuel = dayTx.filter { FuelLogic.isWithdraw($0) && !FuelLogic.isCarFill($0) }
            case .fuelCarFill:
                fuel = dayTx.filter { FuelLogic.isCarFill($0) }
            case .fuelMacroUsage:
                fuel = dayTx.filter { FuelLogic.isVehicleUsage($0) && !FuelLogic.isCarFill($0) }
            default:
                fuel = []
            }
            let fuelSorted = fuel.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            return (mobile, ops, trips, sand, sandRows, macro, fuelSorted)
        }.value

        mobile = bundle.0
        todayOps = bundle.1
        tripUnits = bundle.2
        sandUnit = bundle.3
        sandRows = bundle.4
        macroRows = bundle.5
        fuelRows = bundle.6
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
