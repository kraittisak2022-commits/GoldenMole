import SwiftUI

// MARK: - Briefing (30s)

struct OpsTrendProBriefingStrip: View {
    let pro: OpsTrendAnalyticsPro
    var onCTA: (() -> Void)? = nil

    private var accent: Color { Color(hex: pro.health.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: pro.health.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("BRIEFING · 30 วินาที")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(accent)
                    Text(pro.health.label)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(pro.healthCaption)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !pro.signals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pro.signals) { signal in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(severityColor(signal.severity))
                                .frame(width: 7, height: 7)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(signal.area)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if let cta = pro.primaryCTA {
                Button {
                    onCTA?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.body.weight(.semibold))
                        Text(cta)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }

    private func severityColor(_ s: OpsTrendAlertSeverity) -> Color {
        switch s {
        case .critical: return Color(hex: "#dc2626")
        case .warning: return AppTheme.warning
        case .opportunity: return Color(hex: "#16a34a")
        }
    }
}

// MARK: - Layer toggle

struct OpsTrendProLayerToggle: View {
    @Binding var showFullDetail: Bool

    var body: some View {
        HStack(spacing: 0) {
            layerButton(title: "สรุปผู้บริหาร", selected: !showFullDetail) {
                showFullDetail = false
            }
            layerButton(title: "รายละเอียดเต็ม", selected: showFullDetail) {
                showFullDetail = true
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }

    private func layerButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? AppTheme.ink : AppTheme.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? AppTheme.surface : Color.clear)
                        .shadow(color: selected ? AppTheme.cardShadow : .clear, radius: 4, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Forecast

struct OpsTrendProForecastCard: View {
    let forecast: OpsTrendAnalyticsPro.Forecast

    var body: some View {
        SectionCard(
            "พยากรณ์สิ้นช่วง",
            systemImage: "chart.line.uptrend.xyaxis",
            subtitle: forecast.isLivePeriod
                ? "วัน \(forecast.daysElapsed)/\(forecast.daysTotal) · เหลือ \(forecast.daysRemaining) วัน"
                : "ช่วงย้อนหลัง / ไม่ใช่ช่วงสด"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(forecast.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(forecast.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if forecast.isLivePeriod, forecast.daysTotal > 0 {
                    GeometryReader { geo in
                        let pct = min(1, Double(forecast.daysElapsed) / Double(forecast.daysTotal))
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppTheme.surfaceSoft)
                            Capsule()
                                .fill(hitColor.opacity(0.85))
                                .frame(width: max(8, geo.size.width * pct))
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        metricChip(
                            "คาดเที่ยว",
                            OpsTrendAnalytics.formatCompact(forecast.tripProjected)
                        )
                        metricChip(
                            "เป้า",
                            OpsTrendAnalytics.formatCompact(forecast.tripTarget)
                        )
                        metricChip(
                            "คาดร่อน",
                            OpsTrendAnalytics.formatCompact(forecast.sandProjected)
                        )
                    }
                }
            }
        }
    }

    private var hitColor: Color {
        switch forecast.willHitTripTarget {
        case true: return Color(hex: "#16a34a")
        case false: return Color(hex: "#dc2626")
        case nil: return AppTheme.brand
        }
    }

    private func metricChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }
}

// MARK: - Cost lens

struct OpsTrendProCostLensCard: View {
    let cost: OpsTrendAnalyticsPro.CostLens

    var body: some View {
        SectionCard(
            "คุ้มค่าปฏิบัติการ",
            systemImage: "banknote.fill",
            subtitle: "ค่าแรง + น้ำมัน เทียบเที่ยว/ร่อน"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(cost.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(cost.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if cost.hasData {
                    HStack(spacing: 8) {
                        costChip("ค่าแรง", cost.laborBaht)
                        costChip("น้ำมัน", cost.fuelBaht)
                        if let sand = cost.bahtPerSand {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("บาท/ร่อน")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                                Text(DashboardAggregations.formatCurrency(sand))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppTheme.surfaceSoft)
                            )
                        }
                    }
                }
            }
        }
    }

    private func costChip(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
            Text(DashboardAggregations.formatCurrency(value))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }
}

// MARK: - Watchlist strip (home)

struct OpsTrendHomeWatchlistCard: View {
    let alerts: [OpsTrendAlert]

    var body: some View {
        if alerts.isEmpty {
            EmptyView()
        } else {
            NavigationLink {
                OpsTrendAnalyticsHubView(focus: .both)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.warning)
                        Text("Watchlist วิเคราะห์")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 0)
                        Text("\(alerts.count)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.warning))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    ForEach(alerts.prefix(3)) { alert in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(severityColor(alert.severity))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            Text(alert.title)
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.surface)
                        .shadow(color: AppTheme.cardShadow, radius: 8, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppTheme.warning.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watchlist วิเคราะห์ \(alerts.count) รายการ")
        }
    }

    private func severityColor(_ s: OpsTrendAlertSeverity) -> Color {
        switch s {
        case .critical: return Color(hex: "#dc2626")
        case .warning: return AppTheme.warning
        case .opportunity: return Color(hex: "#16a34a")
        }
    }
}

// MARK: - Share card (image render)

struct OpsTrendShareSummaryCard: View {
    let pro: OpsTrendAnalyticsPro
    let report: OpsTrendReport
    let focus: OpsTrendFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GoldenMole")
                    .font(.caption.weight(.black))
                    .foregroundStyle(AppTheme.brand)
                Spacer()
                Text("วิเคราะห์\(focus == .both ? "" : " · \(focus.label)")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Text(pro.health.label)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(pro.healthCaption)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)

            HStack {
                shareStat("คะแนน", "\(report.scorecard.score)")
                shareStat("เที่ยว", OpsTrendAnalytics.formatCompact(report.trip.total))
                shareStat("ร่อน", OpsTrendAnalytics.formatCompact(report.sand.total))
            }

            if pro.forecast.isLivePeriod {
                Text(pro.forecast.headline)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(pro.forecast.detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }

            if let cta = pro.primaryCTA {
                Text("ทำต่อ: \(cta)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
    }

    private func shareStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Custom range pickers

struct OpsTrendCustomRangeBar: View {
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ช่วงกำหนดเอง")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            HStack {
                DatePicker("เริ่ม", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                    .labelsHidden()
                Text("–")
                    .foregroundStyle(AppTheme.inkMuted)
                DatePicker("สิ้นสุด", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    .labelsHidden()
            }
            .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }
}
