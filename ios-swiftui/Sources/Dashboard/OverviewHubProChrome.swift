import SwiftUI

// MARK: - Delta badge

struct HomeProDeltaBadge: View {
    let label: String?
    var isUp: Bool = true
    /// For costs, up is not always good — pass false to invert colors.
    var upIsGood: Bool = true

    var body: some View {
        if let label, !label.isEmpty {
            let good = upIsGood ? isUp : !isUp
            HStack(spacing: 3) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(good ? Color(hex: "#15803D") : Color(hex: "#B91C1C"))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(good ? Color(hex: "#15803D").opacity(0.12) : Color(hex: "#B91C1C").opacity(0.12))
            )
            .accessibilityLabel(label)
        }
    }
}

// MARK: - Insight strip

struct HomeProInsightStrip: View {
    let insights: [String]
    let alerts: [OverviewAlert]

    var body: some View {
        if !insights.isEmpty || !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.brand)
                    Text("สัญญาณวันนี้")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                }

                if !alerts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(alerts) { alert in
                                alertChip(alert)
                            }
                        }
                    }
                }

                ForEach(Array(insights.prefix(3).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AppTheme.brand)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .background(HomeProCardBackground())
            .accessibilityElement(children: .combine)
        }
    }

    private func alertChip(_ alert: OverviewAlert) -> some View {
        let color: Color = {
            switch alert.severity {
            case .red: return AppTheme.expense
            case .amber: return AppTheme.warning
            case .green: return AppTheme.income
            }
        }()
        return Text(alert.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Checklist

struct HomeProChecklistCard: View {
    let pro: HomeProSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("งานวันนี้ยังขาดอะไร", systemImage: "checklist")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                Text("\(pro.coreCompleted)/\(pro.coreTotal)")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(healthColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(healthColor.opacity(0.14)))
            }

            ProgressView(value: pro.completion)
                .tint(healthColor)
                .accessibilityLabel("ครบ \(pro.coreCompleted) จาก \(pro.coreTotal)")

            ForEach(pro.checklist) { item in
                checklistRow(item)
            }
        }
        .padding(16)
        .background(HomeProCardBackground())
    }

    private var healthColor: Color {
        switch pro.health {
        case .strong: return AppTheme.income
        case .attention: return AppTheme.warning
        case .critical: return AppTheme.expense
        }
    }

    private func checklistRow(_ item: HomeProSnapshot.ChecklistItem) -> some View {
        NavigationLink {
            destination(for: item.destination)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : item.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.isDone ? AppTheme.income : Color(hex: item.accentHex))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(item.isDone ? item.detail : "ยังไม่บันทึก · \(item.detail)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.isDone ? AppTheme.income.opacity(0.08) : Color(hex: item.accentHex).opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title) \(item.isDone ? "บันทึกแล้ว" : "ยังไม่บันทึก")")
    }

    @ViewBuilder
    private func destination(for dest: HomeProSnapshot.ChecklistDestination) -> some View {
        switch dest {
        case .attendance:
            AttendanceHubView()
        case .countTrip:
            CountRecordHubView(initialMode: .trip)
        case .countSand:
            CountRecordHubView(initialMode: .sand)
        case .fuel:
            FuelHubView()
        case .leave:
            LeaveHubView()
        case .events:
            EventHubView()
        case .laborReport:
            CategoryReportScreen(type: .labor)
        case .vehicleReport:
            CategoryReportScreen(type: .vehicle)
        }
    }
}

// MARK: - Command hero

struct HomeProCommandHero: View {
    let greetingName: String
    let dayTitle: String
    let pro: HomeProSnapshot
    let laborBahtLabel: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 160, height: 160)
                .blur(radius: 28)
                .offset(x: 210, y: -50)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMAND CENTER")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.72))
                        Text("สวัสดี \(greetingName)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(dayTitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 8)
                    healthBadge
                }

                HStack(spacing: 8) {
                    kpiChip(
                        title: "เที่ยว",
                        value: "\(Int(pro.trip.current))",
                        delta: pro.trip
                    )
                    kpiChip(
                        title: "ร่อน",
                        value: "\(Int(pro.sand.current))",
                        delta: pro.sand
                    )
                    kpiChip(
                        title: "ค่าแรง",
                        value: shortMoney(pro.labor.current),
                        delta: pro.labor,
                        upIsGood: false
                    )
                }

                if let missing = pro.primaryMissingTitle, pro.health != .strong {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("ยังขาด\(missing)")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )
                    .accessibilityLabel("ยังขาด\(missing)")
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                        Text(laborBahtLabel.isEmpty ? "งานหลักครบแล้ว" : laborBahtLabel)
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: AppTheme.brand.opacity(0.28), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var healthBadge: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(pro.completion))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(pro.coreCompleted)/\(pro.coreTotal)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            Text(pro.health.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityLabel("\(pro.health.label) \(pro.coreCompleted) จาก \(pro.coreTotal)")
    }

    private func kpiChip(
        title: String,
        value: String,
        delta: HomeProSnapshot.MetricDelta,
        upIsGood: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let label = delta.compactCompareLabel {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(chipDeltaColor(isUp: delta.isUp, upIsGood: upIsGood))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
    }

    private func chipDeltaColor(isUp: Bool, upIsGood: Bool) -> Color {
        let good = upIsGood ? isUp : !isUp
        return good ? Color(hex: "#BBF7D0") : Color(hex: "#FECACA")
    }

    private func shortMoney(_ value: Double) -> String {
        if value <= 0 { return "฿0" }
        if value >= 1000 {
            return "฿\(DashboardAggregations.formatNumber(value / 1000))k"
        }
        return DashboardAggregations.formatCurrency(value)
    }
}

// MARK: - Shared card chrome

private struct HomeProCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.surface)
            .shadow(color: AppTheme.cardShadow, radius: 14, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
    }
}
