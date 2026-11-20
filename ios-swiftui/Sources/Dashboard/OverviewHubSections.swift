import SwiftUI

// MARK: - Precomputed Fleet Row Models

struct HomeDrumTripRow: Identifiable, Sendable {
    let id: String
    let vehicleName: String
    var driverLabel: String
    var rounds: Int
    var morning: Int
    var afternoon: Int
}

struct HomeMacroVehicleRow: Identifiable, Sendable {
    let id: String
    let vehicleName: String
    let driverLabel: String
    let dayLabel: String
    let workLabels: [String]
}

// MARK: - GeometryReader-Free Proportional Horizontal Bar

private struct ProportionalBarLayout: Layout {
    let weights: [Double]
    var spacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 6)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0, !subviews.isEmpty else { return }
        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let usableWidth = max(0, bounds.width - totalSpacing)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let weight = index < weights.count ? max(0, weights[index]) : 0
            let remaining = max(0, bounds.maxX - x)
            let isLast = index == subviews.count - 1
            let rawWidth = usableWidth * CGFloat(weight / totalWeight)
            let segWidth = isLast ? remaining : min(remaining, max(6, rawWidth))
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: segWidth, height: bounds.height)
            )
            x += segWidth + spacing
        }
    }
}

// MARK: - Unified Fuel Overview Card

struct HomeFuelOverviewCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let metrics: MobileOpsMetrics
    let mainDieselLiters: Double
    let reserveDieselLiters: Double
    let isFocusToday: Bool
    let summaryDayTitle: String

    private struct FuelBreakdownItem: Identifiable {
        let id: String
        let kind: TodayOpsDetailKind
        let title: String
        let detail: String
        let liters: Double
        let icon: String
    }

    private var tankScaleReference: Double {
        max(1, max(abs(mainDieselLiters), abs(reserveDieselLiters)))
    }

    private var mainTankRatio: CGFloat {
        if mainDieselLiters <= 0 { return 0.12 }
        return CGFloat(min(1, max(0.14, mainDieselLiters / tankScaleReference)))
    }

    private var reserveTankRatio: CGFloat {
        if reserveDieselLiters <= 0 { return 0.12 }
        return CGFloat(min(1, max(0.14, reserveDieselLiters / tankScaleReference)))
    }

    private var breakdownItems: [FuelBreakdownItem] {
        var items: [FuelBreakdownItem] = []
        let fallbackScope = isFocusToday ? "วันนี้" : summaryDayTitle

        if metrics.fuelInLiters > 0 {
            items.append(FuelBreakdownItem(
                id: "fuelIn",
                kind: .fuelStockIn,
                title: "เพิ่มน้ำมัน",
                detail: "รับเข้าถังหลัก",
                liters: metrics.fuelInLiters,
                icon: "arrow.down.to.line.circle.fill"
            ))
        }
        if metrics.fuelWithdrawLiters > 0 || metrics.fuelWithdrawCount > 0 {
            items.append(FuelBreakdownItem(
                id: "fuelWithdraw",
                kind: .fuelWithdraw,
                title: "เบิกน้ำมัน",
                detail: metrics.fuelWithdrawCount > 0 ? "\(metrics.fuelWithdrawCount) ครั้ง" : fallbackScope,
                liters: metrics.fuelWithdrawLiters,
                icon: "arrow.up.right.circle.fill"
            ))
        }
        if metrics.fuelCarFillLiters > 0 || metrics.fuelCarFillCount > 0 {
            items.append(FuelBreakdownItem(
                id: "fuelCarFill",
                kind: .fuelCarFill,
                title: "เติมน้ำมันรถยนต์",
                detail: metrics.fuelCarFillCount > 0 ? "\(metrics.fuelCarFillCount) ครั้ง" : fallbackScope,
                liters: metrics.fuelCarFillLiters,
                icon: "car.fill"
            ))
        }
        if metrics.fuelMacroUsageLiters > 0 || metrics.fuelMacroVehicles > 0 {
            items.append(FuelBreakdownItem(
                id: "fuelMacro",
                kind: .fuelMacroUsage,
                title: "น้ำมันรถแม็คโคร",
                detail: metrics.fuelMacroVehicles > 0 ? "\(metrics.fuelMacroVehicles) คัน" : fallbackScope,
                liters: metrics.fuelMacroUsageLiters,
                icon: "hammer.fill"
            ))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                CategoryReportScreen(type: .fuel)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "fuelpump.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.fuel)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AppTheme.fuel.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("น้ำมันและสต็อกถัง")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("ยอดคงเหลือรวมและรายการ\(isFocusToday ? "วันนี้" : "")")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.985))
            .accessibilityHint("แตะเพื่อดูรายละเอียดน้ำมัน")

            // Dual tank stock balances with animated proportion bars
            HStack(spacing: 10) {
                tankTile(
                    title: "ถังหลัก",
                    liters: mainDieselLiters,
                    ratio: mainTankRatio,
                    accent: mainDieselLiters < 0 ? AppTheme.expense : AppTheme.fuel
                )
                tankTile(
                    title: "ถังสำรอง",
                    liters: reserveDieselLiters,
                    ratio: reserveTankRatio,
                    accent: reserveDieselLiters < 0 ? AppTheme.expense : HomeSemanticColor.tealAccent
                )
            }

            if mainDieselLiters < 0 {
                HStack(spacing: 6) {
                    HomeLivePulseDot(color: AppTheme.expense, size: 5)
                    Text("ถังหลักติดลบ — ตรวจรายการรับเข้า (StockIn) และการเบิก/โอนซ้ำ")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppTheme.expense)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.expense.opacity(0.1))
                )
            }

            // Flow summary bar
            HStack(spacing: 0) {
                flowMetric(
                    title: isFocusToday ? "ใช้ไปวันนี้" : "ใช้ไป",
                    value: "\(DashboardAggregations.formatNumber(metrics.fuelOutLiters)) L",
                    numericKey: metrics.fuelOutLiters,
                    note: "ไม่รวมโอนสำรอง",
                    accent: AppTheme.ink
                )

                Rectangle()
                    .fill(AppTheme.hairline)
                    .frame(width: 1, height: 34)

                flowMetric(
                    title: isFocusToday ? "รับเข้าวันนี้" : "รับเข้า",
                    value: "\(DashboardAggregations.formatNumber(metrics.fuelInLiters)) L",
                    numericKey: metrics.fuelInLiters,
                    note: metrics.fuelWithdrawLiters > 0
                        ? "เบิกสำรอง \(DashboardAggregations.formatNumber(metrics.fuelWithdrawLiters)) L"
                        : "เข้าสต็อก",
                    accent: AppTheme.fuel
                )
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceSoft.opacity(0.65))
            )

            // Inline drill-down rows for active fuel operations
            if !breakdownItems.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(breakdownItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                                .padding(.leading, 36)
                        }
                        NavigationLink {
                            TodayOpsDetailScreen(kind: item.kind)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.caption.weight(.semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(AppTheme.fuel)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(AppTheme.fuel.opacity(0.1))
                                    )

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(item.detail)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.inkMuted)
                                }

                                Spacer(minLength: 6)

                                Text("\(DashboardAggregations.formatNumber(item.liters)) L")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(AppTheme.ink)
                                    .contentTransition(.numericText())
                                    .animation(.snappy(duration: 0.35), value: item.liters)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AppTheme.inkMuted.opacity(0.7))
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.985))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .homeCardSurface()
    }

    private func tankTile(title: String, liters: Double, ratio: CGFloat, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
            }
            Text("\(DashboardAggregations.formatNumber(liters)) L")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(liters < 0 ? AppTheme.expense : AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: liters)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(accent.opacity(0.15))
                Capsule()
                    .fill(accent)
                    .scaleEffect(x: ratio, y: 1, anchor: .leading)
                    .animation(
                        reduceMotion ? .none : .spring(duration: 0.5, bounce: 0.1),
                        value: ratio
                    )
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(liters < 0 ? AppTheme.expense.opacity(0.35) : AppTheme.hairline, lineWidth: 1)
        )
    }

    private func flowMetric(
        title: String,
        value: String,
        numericKey: Double,
        note: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: numericKey)
            Text(note)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

// MARK: - Cost Pair (Labor & Vehicle)

struct HomeCostPairSection: View {
    let laborBaht: Double
    let presentCount: Int
    let vehicleBaht: Double
    let showLabor: Bool
    let showVehicle: Bool
    let laborDeltaLabel: String?
    let laborDeltaIsUp: Bool

    var body: some View {
        if showLabor || showVehicle {
            HStack(spacing: 12) {
                if showLabor {
                    NavigationLink {
                        CategoryReportScreen(type: .labor)
                    } label: {
                        costCard(
                            title: "ค่าแรง",
                            value: DashboardAggregations.formatCurrency(laborBaht),
                            numericKey: laborBaht,
                            subtitle: "มาทำงาน \(presentCount) คน",
                            icon: "banknote.fill",
                            accent: AppTheme.labor,
                            deltaLabel: laborDeltaLabel,
                            deltaIsUp: laborDeltaIsUp,
                            deltaUpIsGood: false
                        )
                    }
                    .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.965))
                    .accessibilityHint("แตะเพื่อดูรายละเอียดค่าแรง")
                }

                if showVehicle {
                    NavigationLink {
                        CategoryReportScreen(type: .vehicle)
                    } label: {
                        costCard(
                            title: "ค่าใช้รถ",
                            value: DashboardAggregations.formatCurrency(vehicleBaht),
                            numericKey: vehicleBaht,
                            subtitle: "ค่าเที่ยว / ค่าขับ",
                            icon: "truck.box.fill",
                            accent: AppTheme.vehicle
                        )
                    }
                    .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.965))
                    .accessibilityHint("แตะเพื่อดูรายละเอียดการใช้รถ")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func costCard(
        title: String,
        value: String,
        numericKey: Double,
        subtitle: String,
        icon: String,
        accent: Color,
        deltaLabel: String? = nil,
        deltaIsUp: Bool = true,
        deltaUpIsGood: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.inkMuted.opacity(0.7))
            }

            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: numericKey)

            if deltaLabel != nil {
                HomeProDeltaBadge(label: deltaLabel, isUp: deltaIsUp, upIsGood: deltaUpIsGood)
            }

            Spacer(minLength: 0)

            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .homeCardSurface(cornerRadius: 16)
    }
}

// MARK: - Daily Events Card

struct HomeDailyEventsCard: View {
    let rows: [Transaction]
    let title: String

    private var hasUrgent: Bool {
        rows.contains { EventLogic.Priority.from(raw: $0.eventPriority) == .urgent }
    }

    var body: some View {
        if !rows.isEmpty {
            NavigationLink {
                EventHubView()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(hasUrgent ? AppTheme.expense : AppTheme.purple)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill((hasUrgent ? AppTheme.expense : AppTheme.purple).opacity(0.12))
                            )
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Text("\(rows.count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(hasUrgent ? AppTheme.expense : AppTheme.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((hasUrgent ? AppTheme.expense : AppTheme.purple).opacity(0.12)))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                            if index > 0 {
                                Rectangle()
                                    .fill(AppTheme.hairline)
                                    .frame(height: 1)
                                    .padding(.vertical, 8)
                            }
                            eventRow(event)
                        }
                    }
                }
                .padding(16)
                .homeCardSurface(borderColor: hasUrgent ? AppTheme.expense.opacity(0.28) : nil)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeTactileButtonStyle())
            .accessibilityHint("แตะเพื่อเปิดเมนูเหตุการณ์")
        }
    }

    private func eventRow(_ t: Transaction) -> some View {
        let kind = EventLogic.EventKind.from(raw: t.eventType)
        let priority = EventLogic.Priority.from(raw: t.eventPriority)
        let text = EventLogic.stripRecorder(t.description)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.accent)
                Text(kind.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(kind.accent)
                if priority == .urgent {
                    HStack(spacing: 4) {
                        HomeLivePulseDot(color: AppTheme.expense, size: 4.5)
                        Text("ด่วน")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.expense.opacity(0.14)))
                    .foregroundStyle(AppTheme.expense)
                }
                Spacer(minLength: 0)
            }

            Text(text.isEmpty ? "—" : text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Focused Field Operations Grid

struct HomeOpsMetricsSection: View {
    let title: String
    let metrics: MobileOpsMetrics
    let homePro: HomeProSnapshot
    let leaveNamesToday: [String]
    let isFocusToday: Bool
    let summaryDayTitle: String

    private var showTrips: Bool { metrics.tripRounds > 0 || metrics.tripVehicles > 0 }
    private var showSand: Bool { metrics.sandRounds > 0 || metrics.sandWashedCubic > 0 }
    private var showAttendance: Bool { metrics.presentCount > 0 || metrics.leaveCount > 0 || metrics.absentCount > 0 }
    private var showMacro: Bool { metrics.macroUsageCount > 0 || metrics.macroVehicles > 0 }
    private var showLeave: Bool { metrics.leaveCount > 0 }

    private var hasAny: Bool {
        showTrips || showSand || showAttendance || showMacro || showLeave
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if hasAny {
            VStack(alignment: .leading, spacing: 10) {
                HomeSectionHeader(title: title, trailing: "แตะดูรายละเอียด")

                LazyVGrid(columns: columns, spacing: 12) {
                    if showTrips {
                        NavigationLink {
                            TodayOpsDetailScreen(kind: .trips)
                        } label: {
                            HomeOpsMetricTile(
                                title: "เที่ยวรถ",
                                value: "\(metrics.tripRounds)",
                                numericKey: Double(metrics.tripRounds),
                                unit: "เที่ยว",
                                detail: "\(metrics.tripVehicles) คัน · \(DashboardAggregations.formatNumber(metrics.tripCubic)) คิว",
                                accent: AppTheme.vehicle,
                                systemImage: "truck.box.fill",
                                deltaLabel: homePro.trip.compactCompareLabel,
                                deltaIsUp: homePro.trip.isUp
                            )
                        }
                        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
                    }

                    if showSand {
                        NavigationLink {
                            TodayOpsDetailScreen(kind: .sand)
                        } label: {
                            HomeOpsMetricTile(
                                title: "ร่อนทราย",
                                value: "\(metrics.sandRounds)",
                                numericKey: Double(metrics.sandRounds),
                                unit: "รอบ",
                                detail: "ล้าง \(DashboardAggregations.formatNumber(metrics.sandWashedCubic)) คิว",
                                accent: AppTheme.sand,
                                systemImage: "drop.fill",
                                deltaLabel: homePro.sand.compactCompareLabel,
                                deltaIsUp: homePro.sand.isUp
                            )
                        }
                        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
                    }

                    if showAttendance {
                        NavigationLink {
                            TodayOpsDetailScreen(kind: .attendance)
                        } label: {
                            HomeOpsMetricTile(
                                title: "เช็คชื่อ",
                                value: "\(metrics.presentCount)",
                                numericKey: Double(metrics.presentCount),
                                unit: "คน",
                                detail: "ลา \(metrics.leaveCount) · ขาด \(metrics.absentCount)",
                                accent: AppTheme.labor,
                                systemImage: "person.3.fill",
                                deltaLabel: homePro.present.compactCompareLabel,
                                deltaIsUp: homePro.present.isUp
                            )
                        }
                        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
                    }

                    if showMacro {
                        NavigationLink {
                            TodayOpsDetailScreen(kind: .macro)
                        } label: {
                            HomeOpsMetricTile(
                                title: "แม็คโคร",
                                value: "\(metrics.macroUsageCount)",
                                numericKey: Double(metrics.macroUsageCount),
                                unit: "ครั้ง",
                                detail: "\(metrics.macroVehicles) คัน",
                                accent: HomeSemanticColor.tealAccent,
                                systemImage: "hammer.fill"
                            )
                        }
                        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
                    }

                    if showLeave {
                        NavigationLink {
                            TodayOpsDetailScreen(kind: .leave)
                        } label: {
                            HomeOpsMetricTile(
                                title: "ลางาน",
                                value: "\(metrics.leaveCount)",
                                numericKey: Double(metrics.leaveCount),
                                unit: "คน",
                                detail: leaveNamesToday.isEmpty
                                    ? (isFocusToday ? "วันนี้" : summaryDayTitle)
                                    : leaveNamesToday.joined(separator: " · "),
                                accent: AppTheme.warning,
                                systemImage: "calendar.badge.minus"
                            )
                        }
                        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
                    }
                }
            }
        }
    }
}

private struct HomeOpsMetricTile: View {
    let title: String
    let value: String
    let numericKey: Double
    let unit: String
    let detail: String
    let accent: Color
    let systemImage: String
    var deltaLabel: String? = nil
    var deltaIsUp: Bool = true
    var deltaUpIsGood: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.inkMuted.opacity(0.7))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: numericKey)
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            if deltaLabel != nil {
                HomeProDeltaBadge(label: deltaLabel, isUp: deltaIsUp, upIsGood: deltaUpIsGood)
            }

            Spacer(minLength: 0)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .homeCardSurface(cornerRadius: 16)
    }
}

// MARK: - Fleet Activity (Drum & Macro)

struct HomeFleetSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let drumRows: [HomeDrumTripRow]
    let macroRows: [HomeMacroVehicleRow]

    private var maxDrumRounds: Int {
        max(1, drumRows.map(\.rounds).max() ?? 1)
    }

    var body: some View {
        if !drumRows.isEmpty || !macroRows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(
                    title: "เครื่องจักรและรถวิ่งงาน",
                    trailing: fleetSummaryTrailing
                )

                if !drumRows.isEmpty {
                    drumCard
                }

                if !macroRows.isEmpty {
                    macroCard
                }
            }
        }
    }

    private var fleetSummaryTrailing: String {
        var parts: [String] = []
        if !drumRows.isEmpty { parts.append("ดรัม \(drumRows.count)") }
        if !macroRows.isEmpty { parts.append("แม็คโคร \(macroRows.count)") }
        return parts.joined(separator: " · ")
    }

    private var drumCard: some View {
        NavigationLink {
            CountRecordHubView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.vehicle)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AppTheme.vehicle.opacity(0.12))
                        )
                    Text("รถดรัม")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    PillBadge(text: "\(drumRows.count) คัน", color: AppTheme.vehicle)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

                VStack(spacing: 0) {
                    ForEach(Array(drumRows.enumerated()), id: \.element.id) { index, row in
                        let ratio = CGFloat(min(1, max(0.08, Double(row.rounds) / Double(maxDrumRounds))))
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.vehicleName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(1)
                                    Text(row.driverLabel)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkMuted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(row.rounds) เที่ยว")
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(AppTheme.vehicle)
                                        .contentTransition(.numericText())
                                        .animation(.snappy(duration: 0.35), value: row.rounds)
                                    if row.morning > 0 || row.afternoon > 0 {
                                        Text("เช้า \(row.morning) · บ่าย \(row.afternoon)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(AppTheme.inkMuted)
                                    }
                                }
                            }

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppTheme.vehicle.opacity(0.12))
                                Capsule()
                                    .fill(AppTheme.vehicle.opacity(index == 0 ? 0.92 : 0.65))
                                    .scaleEffect(x: ratio, y: 1, anchor: .leading)
                                    .animation(
                                        reduceMotion ? .none : .spring(duration: 0.45, bounce: 0.1),
                                        value: ratio
                                    )
                            }
                            .frame(height: 3.5)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(16)
            .homeCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeTactileButtonStyle())
        .accessibilityHint("แตะเพื่อเปิดเมนูบันทึกจำนวนเที่ยวรถ")
    }

    private var macroCard: some View {
        let accent = HomeSemanticColor.tealAccent
        return NavigationLink {
            MacroVehicleHubView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "hammer.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(accent.opacity(0.12))
                        )
                    Text("รถแม็คโคร")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    PillBadge(text: "\(macroRows.count) คัน", color: accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

                VStack(spacing: 0) {
                    ForEach(Array(macroRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.vehicleName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(2)
                                    Text(row.driverLabel)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkMuted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(row.dayLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(accent.opacity(0.12)))
                            }

                            if row.workLabels.isEmpty {
                                Text("ยังไม่ระบุรายละเอียดงาน")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            } else {
                                Text(row.workLabels.joined(separator: " · "))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(AppTheme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
            .padding(16)
            .homeCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeTactileButtonStyle())
        .accessibilityHint("แตะเพื่อเปิดเมนูการใช้รถแม็คโคร")
    }
}

// MARK: - Unified Attendance & Staff Roster Card

struct HomeStaffCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let todayOps: TodayOpsSnapshot
    let leaveNamesToday: [String]
    @Binding var showAllWorkingStaff: Bool

    private var hasAttendanceSummary: Bool {
        todayOps.presentCount > 0 || todayOps.leaveCount > 0 || todayOps.absentCount > 0
    }

    private struct AttendanceSegment: Identifiable {
        let id: String
        let weight: Double
        let color: Color
    }

    private var attendanceSegments: [AttendanceSegment] {
        var out: [AttendanceSegment] = []
        if todayOps.presentCount > 0 {
            out.append(AttendanceSegment(id: "work", weight: Double(todayOps.presentCount), color: AppTheme.income))
        }
        if todayOps.leaveCount > 0 {
            out.append(AttendanceSegment(id: "leave", weight: Double(todayOps.leaveCount), color: AppTheme.warning))
        }
        if todayOps.absentCount > 0 {
            out.append(AttendanceSegment(id: "absent", weight: Double(todayOps.absentCount), color: AppTheme.expense))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                AttendanceHubView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.labor)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(AppTheme.labor.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("พนักงานและเช็คชื่อ")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("พนักงานท่าทรายและคนขับรถแม็คโคร")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.985))
            .accessibilityHint("แตะเพื่อดูรายละเอียดเช็คชื่อ")

            if hasAttendanceSummary {
                VStack(spacing: 10) {
                    if !attendanceSegments.isEmpty {
                        ProportionalBarLayout(weights: attendanceSegments.map(\.weight), spacing: 3) {
                            ForEach(attendanceSegments) { seg in
                                Capsule()
                                    .fill(seg.color)
                            }
                        }
                        .frame(height: 6)
                        .animation(
                            reduceMotion ? .none : .spring(duration: 0.45, bounce: 0.12),
                            value: "\(todayOps.presentCount)-\(todayOps.leaveCount)-\(todayOps.absentCount)"
                        )
                    }

                    HStack(spacing: 8) {
                        attendanceChip(count: todayOps.presentCount, title: "มาทำงาน", color: AppTheme.income)
                        attendanceChip(count: todayOps.leaveCount, title: "ลางาน", color: AppTheme.warning)
                        attendanceChip(count: todayOps.absentCount, title: "ขาดงาน", color: AppTheme.expense)
                    }
                }

                if !leaveNamesToday.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "calendar.badge.minus")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.top, 2)
                        Text("ผู้ลา: \(leaveNamesToday.joined(separator: " · "))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.warning.opacity(0.09))
                    )
                }
            }

            if todayOps.staffRows.isEmpty {
                EmptyStateView(
                    title: "ยังไม่มีข้อมูลเช็คชื่อวันนี้",
                    message: "นับเฉพาะพนักงานท่าทรายและคนขับรถแม็คโคร",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            } else {
                staffRosterList
            }
        }
        .padding(16)
        .homeCardSurface()
    }

    @ViewBuilder
    private var staffRosterList: some View {
        let working = todayOps.staffRows.filter { $0.status == .work }
        let onLeave = todayOps.staffRows.filter { $0.status == .leave }
        let absent = todayOps.staffRows.filter { $0.status == .absent }
        let visibleWorking = showAllWorkingStaff ? working : Array(working.prefix(3))

        VStack(alignment: .leading, spacing: 8) {
            if !working.isEmpty {
                staffGroupHeader("มาทำงาน", count: working.count, color: AppTheme.income)
                VStack(spacing: 0) {
                    ForEach(Array(visibleWorking.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
                        staffRowView(row)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if working.count > 3 {
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.28)) {
                            showAllWorkingStaff.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showAllWorkingStaff ? "ย่อรายชื่อ" : "ดูทั้งหมด (\(working.count) คน)")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(showAllWorkingStaff ? 180 : 0))
                                .animation(reduceMotion ? .none : .snappy(duration: 0.26), value: showAllWorkingStaff)
                        }
                        .foregroundStyle(AppTheme.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.brand.opacity(0.08))
                        )
                    }
                    .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.98))
                    .sensoryFeedback(.selection, trigger: showAllWorkingStaff)
                }
            }

            if !onLeave.isEmpty {
                if !working.isEmpty {
                    Rectangle().fill(AppTheme.hairline).frame(height: 1).padding(.vertical, 4)
                }
                staffGroupHeader("ลางาน", count: onLeave.count, color: AppTheme.warning)
                VStack(spacing: 0) {
                    ForEach(Array(onLeave.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
                        staffRowView(row)
                    }
                }
            }

            if !absent.isEmpty {
                if !working.isEmpty || !onLeave.isEmpty {
                    Rectangle().fill(AppTheme.hairline).frame(height: 1).padding(.vertical, 4)
                }
                staffGroupHeader("ขาดงาน", count: absent.count, color: AppTheme.expense)
                VStack(spacing: 0) {
                    ForEach(Array(absent.prefix(12).enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
                        staffRowView(row)
                    }
                }
                if absent.count > 12 {
                    Text("และอีก \(absent.count - 12) คน")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func attendanceChip(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(count > 0 ? color : AppTheme.inkMuted)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: count)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }

    private func staffGroupHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.inkSecondary)
            Spacer()
            PillBadge(text: "\(count) คน", color: color)
        }
    }

    private func staffRowView(_ row: TodayOpsSnapshot.StaffRow) -> some View {
        let color = staffStatusColor(row.status)
        return HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(String(row.name.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                if !row.workLabels.isEmpty {
                    Text(row.workLabels.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if row.status == .work && row.wage > 0 {
                    Text(DashboardAggregations.formatCurrency(row.wage))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
                Text(row.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(.vertical, 8)
    }

    private func staffStatusColor(_ status: TodayOpsSnapshot.StaffRow.Status) -> Color {
        switch status {
        case .work: return AppTheme.income
        case .leave: return AppTheme.warning
        case .absent: return AppTheme.expense
        }
    }
}

// MARK: - Multi-Day Period Summary Card

struct HomePeriodRangeCard: View {
    let range: MobileOpsMetrics
    let periodLabel: String

    private var showTrips: Bool { range.tripRounds > 0 || range.tripVehicles > 0 }
    private var showSand: Bool { range.sandRounds > 0 || range.sandWashedCubic > 0 }
    private var showAttendance: Bool { range.attendanceDays > 0 || range.presentCount > 0 }
    private var showMacro: Bool { range.macroUsageCount > 0 || range.macroVehicles > 0 }
    private var showFuel: Bool { range.fuelInLiters > 0 || range.fuelOutLiters > 0 }
    private var hasAny: Bool { showTrips || showSand || showAttendance || showMacro || showFuel }

    var body: some View {
        if hasAny {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("รวมช่วงที่เลือก")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(periodLabel)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 8) {
                    if showTrips {
                        periodRow("เที่ยวรถ", "\(range.tripRounds) เที่ยว · \(range.tripVehicles) คัน")
                    }
                    if showSand {
                        periodRow("ร่อนทราย", "\(range.sandRounds) รอบ · ล้าง \(DashboardAggregations.formatNumber(range.sandWashedCubic)) คิว")
                    }
                    if showAttendance {
                        periodRow("เช็คชื่อ", "เฉลี่ย \(range.presentCount) คน/วัน · \(range.attendanceDays) วัน")
                    }
                    if showMacro {
                        periodRow("แม็คโคร", "\(range.macroUsageCount) ครั้ง · \(range.macroVehicles) คัน")
                    }
                    if showFuel {
                        periodRow(
                            "น้ำมัน",
                            "เข้า \(DashboardAggregations.formatNumber(range.fuelInLiters)) L · ออก \(DashboardAggregations.formatNumber(range.fuelOutLiters)) L"
                        )
                    }
                }
            }
            .padding(16)
            .homeCardSurface()
        }
    }

    private func periodRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
                .frame(width: 66, alignment: .leading)
            Text(detail)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
