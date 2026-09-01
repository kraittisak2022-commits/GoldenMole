import SwiftUI

/// Monthly summary: car fill + generator · sand-sieve · macro usage (ops menu «สรุปรายงาน»).
struct FuelMonthlyReportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visibleMonth: Date = {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    @State private var report = FuelLogic.MonthlyUsageReport.empty
    @State private var expandedCarDay: String?
    @State private var expandedMacroDay: String?

    private let carColor = Color(hex: "#0d9488")
    private let machineColor = Color(hex: "#DB2777")
    private let macroColor = Color(hex: "#0F766E")
    private let generatorColor = Color(hex: "#CA8A04")

    var body: some View {
        VStack(spacing: 0) {
            monthBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryChips
                    if report.totalLiters > 0 {
                        pieSection
                    } else {
                        EmptyStateView(
                            title: "ยังไม่มีข้อมูลใน\(monthTitle)",
                            message: "เมื่อมีการเติมรถยนต์ ปั่นไฟ ใช้เครื่องร่อน หรือใช้แม็คโคร จะสรุปที่นี่",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                    carAndGeneratorSection
                    groupSectionSimple(
                        title: "เครื่องจักร (เครื่องร่อน)",
                        total: report.machineLiters,
                        color: machineColor,
                        days: report.machineByDay
                    )
                    macroSection
                }
                .padding(AppTheme.spaceLG)
            }
            .scrollContentBackground(.hidden)
        }
        .background(DashboardBackground())
        .navigationTitle("สรุปรายงาน")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(monthKey)-\(appState.transactionsRevision)") {
            await reload()
        }
    }

    // MARK: - Month bar

    private var monthBar: some View {
        HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.surfaceSoft))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เดือนก่อน")

            VStack(spacing: 2) {
                Text(monthTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                if !isCurrentMonth {
                    Button("เดือนนี้") { goThisMonth() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.fuel)
                }
            }
            .frame(maxWidth: .infinity)

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(canGoForward ? AppTheme.ink : AppTheme.inkMuted.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.surfaceSoft))
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .accessibilityLabel("เดือนถัดไป")
        }
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.vertical, 12)
        .background(AppTheme.surfaceSoft.opacity(0.85))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
        }
    }

    // MARK: - Summary

    private var summaryChips: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                chip(title: "รวมเดือนนี้", value: report.totalLiters, accent: AppTheme.fuel)
                chip(title: "รถยนต์ · ปั่นไฟ", value: report.carAndGeneratorLiters, accent: carColor)
                chip(title: "เครื่องร่อน", value: report.machineLiters, accent: machineColor)
                chip(title: "รถแม็คโคร", value: report.macroLiters, accent: macroColor)
            }
        }
    }

    private func chip(title: String, value: Double, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
            Text("\(DashboardAggregations.formatNumber(value)) L")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.1))
        )
    }

    private var pieSection: some View {
        let slices = [
            ChartSlice(label: "รถยนต์·ปั่นไฟ", value: report.carAndGeneratorLiters, colorHex: "#0d9488"),
            ChartSlice(label: "เครื่องร่อน", value: report.machineLiters, colorHex: "#DB2777"),
            ChartSlice(label: "แม็คโคร", value: report.macroLiters, colorHex: "#0F766E"),
        ].filter { $0.value > 0 }

        return SectionCard("สัดส่วน (ลิตร)", systemImage: "chart.pie.fill") {
            if slices.isEmpty {
                Text("ยังไม่มีลิตรในเดือนนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                DonutChartView(slices: slices).frame(height: 160)
                HStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: slice.colorHex)).frame(width: 8, height: 8)
                            Text(slice.label)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Car + generator

    private var carAndGeneratorSection: some View {
        SectionCard("เติมน้ำมันรถยนต์ · ปั่นไฟเล็ก", systemImage: "list.bullet") {
            HStack {
                Text("รวม")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Text("\(DashboardAggregations.formatNumber(report.carAndGeneratorLiters)) L")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(carColor)
            }
            if report.carAndGeneratorLiters <= 0 {
                Text("ไม่มีรายการในเดือนนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                HStack(spacing: 8) {
                    subTotalChip(title: "รถยนต์", value: report.carFillLiters, color: carColor)
                    subTotalChip(title: "ปั่นไฟเล็ก", value: report.generatorLiters, color: generatorColor)
                }
                .padding(.top, 4)

                if !report.carFillByVehicle.isEmpty {
                    Text("ตามรายการ")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.top, 6)
                    ForEach(report.carFillByVehicle) { row in
                        HStack {
                            Text(row.vehicleId)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("\(DashboardAggregations.formatNumber(row.liters)) L")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(row.vehicleId == "ปั่นไฟเล็ก" ? generatorColor : carColor)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Text("รายวัน · กดเพื่อดูรายการ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 8)

                ForEach(report.carFillByDay) { row in
                    expandableDayRow(
                        row: row,
                        color: carColor,
                        expanded: Binding(
                            get: { expandedCarDay == row.date },
                            set: { expandedCarDay = $0 ? row.date : nil }
                        )
                    )
                }
            }
        }
    }

    private func subTotalChip(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            Text("\(DashboardAggregations.formatNumber(value)) L")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Macro

    private var macroSection: some View {
        SectionCard("รถแม็คโคร", systemImage: "list.bullet") {
            HStack {
                Text("รวม")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Text("\(DashboardAggregations.formatNumber(report.macroLiters)) L")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(macroColor)
            }
            if report.macroLiters <= 0 {
                Text("ไม่มีรายการในเดือนนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                if !report.macroByVehicle.isEmpty {
                    Text("ตามรถ")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.top, 4)
                    ForEach(report.macroByVehicle) { row in
                        HStack {
                            Text(row.vehicleId)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("\(DashboardAggregations.formatNumber(row.liters)) L")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(macroColor)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Text("รายวัน · กดเพื่อดูรายการ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 8)
                ForEach(report.macroByDay) { row in
                    expandableDayRow(
                        row: row,
                        color: macroColor,
                        expanded: Binding(
                            get: { expandedMacroDay == row.date },
                            set: { expandedMacroDay = $0 ? row.date : nil }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Simple day list (machine)

    private func groupSectionSimple(
        title: String,
        total: Double,
        color: Color,
        days: [FuelLogic.MonthlyDayRow]
    ) -> some View {
        SectionCard(title, systemImage: "list.bullet") {
            HStack {
                Text("รวม")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Text("\(DashboardAggregations.formatNumber(total)) L")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
            }
            if total <= 0 {
                Text("ไม่มีรายการในเดือนนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                Text("รายวัน")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 6)
                ForEach(days) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DashboardAggregations.thaiDateLong(row.date))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            if let sub = row.subtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                        }
                        Spacer()
                        Text("\(DashboardAggregations.formatNumber(row.liters)) L")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - Expandable day

    private func expandableDayRow(
        row: FuelLogic.MonthlyDayRow,
        color: Color,
        expanded: Binding<Bool>
    ) -> some View {
        DisclosureGroup(isExpanded: expanded) {
            if row.items.isEmpty {
                Text("ไม่มีรายการย่อย")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.vertical, 4)
            } else {
                ForEach(row.items) { item in
                    lineItemRow(item, accent: color)
                }
            }
        } label: {
            HStack {
                Text(DashboardAggregations.thaiDateLong(row.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(DashboardAggregations.formatNumber(row.liters)) L")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
        }
        .tint(AppTheme.inkMuted)
        .padding(.vertical, 2)
    }

    private func lineItemRow(_ item: FuelLogic.MonthlyLineItem, accent: Color) -> some View {
        let color: Color = {
            switch item.kind {
            case .generator: return generatorColor
            case .carFill, .macro: return accent
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Text(lineSubtitle(item))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            Text("\(DashboardAggregations.formatNumber(item.liters)) L")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }

    private func lineSubtitle(_ item: FuelLogic.MonthlyLineItem) -> String {
        var parts: [String] = []
        switch item.kind {
        case .carFill: parts.append("เติมรถยนต์")
        case .generator: parts.append("ปั่นไฟเล็ก")
        case .macro: parts.append("ใช้แม็คโคร")
        }
        if let tank = item.tankLabel, !tank.isEmpty { parts.append(tank) }
        if let time = item.time, !time.isEmpty { parts.append(time) }
        if let detail = item.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Month helpers

    private var monthKey: String {
        let cal = DashboardAggregations.gregorian
        let y = cal.component(.year, from: visibleMonth)
        let m = cal.component(.month, from: visibleMonth)
        return String(format: "%04d-%02d", y, m)
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

    private var canGoForward: Bool { !isCurrentMonth }

    private func shiftMonth(_ delta: Int) {
        let cal = DashboardAggregations.gregorian
        guard let next = cal.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        let nextStart = cal.date(from: cal.dateComponents([.year, .month], from: next)) ?? next
        let thisStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        if nextStart > thisStart { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            visibleMonth = nextStart
            expandedCarDay = nil
            expandedMacroDay = nil
        }
    }

    private func goThisMonth() {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: Date())
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            visibleMonth = cal.date(from: comps) ?? Date()
            expandedCarDay = nil
            expandedMacroDay = nil
        }
    }

    private func reload() async {
        let month = visibleMonth
        let txs = appState.transactions
        let cars = appState.settings.cars
        let catalog = appState.settings.vehicleCatalog
        report = await Task.detached(priority: .userInitiated) {
            FuelLogic.buildMonthly(monthStart: month, transactions: txs, cars: cars, catalog: catalog)
        }.value
    }
}
