import SwiftUI

/// Sand stock pond dashboard — remaining / in / out in cubic meters (คิว).
struct SandStockHubView: View {
    @Environment(AppState.self) private var appState
    @State private var scope = ReportDateScope()
    @State private var snapshot = SandStockLogic.Snapshot.empty
    @State private var openingDraft = ""
    @State private var showOpeningEditor = false

    private var accent: Color { AppTheme.sand }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReportDateBar(scope: $scope)

                remainingHero

                paceBanner

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    StatCardView(
                        title: "ขนเข้าบ่อ",
                        value: "\(fmt(snapshot.periodInCubic))",
                        subtitle: "\(SandStockLogic.unitLabel) · \(scope.title)",
                        accent: AppTheme.income,
                        systemImage: "arrow.down.to.line.circle.fill"
                    )
                    StatCardView(
                        title: "ร่อนออก",
                        value: "\(fmt(snapshot.periodOutCubic))",
                        subtitle: "\(SandStockLogic.unitLabel) · \(scope.title)",
                        accent: AppTheme.expense,
                        systemImage: "arrow.up.right.circle.fill"
                    )
                    StatCardView(
                        title: "สุทธิช่วงนี้",
                        value: signed(snapshot.periodNetCubic),
                        subtitle: SandStockLogic.unitLabel,
                        accent: snapshot.periodNetCubic >= 0 ? AppTheme.income : AppTheme.warning,
                        systemImage: "arrow.left.arrow.right.circle.fill"
                    )
                    StatCardView(
                        title: "วันนี้",
                        value: "+\(fmt(snapshot.todayInCubic)) / −\(fmt(snapshot.todayOutCubic))",
                        subtitle: SandStockLogic.unitLabel,
                        accent: AppTheme.info,
                        systemImage: "sun.max.fill"
                    )
                }

                if !snapshot.series.isEmpty {
                    chartCard(
                        title: "ขนเข้า vs ร่อนออก",
                        subtitle: "หน่วย: \(SandStockLogic.unitLabel) (ลบ.ม.)"
                    ) {
                        GroupedBarChartView(
                            labels: chartLabels,
                            seriesA: snapshot.series.map(\.inCubic),
                            seriesB: snapshot.series.map(\.outCubic),
                            colorA: AppTheme.income,
                            colorB: AppTheme.expense,
                            labelA: "ขนเข้า",
                            labelB: "ร่อนออก"
                        )
                    }

                    chartCard(
                        title: "คงเหลือท้ายวัน",
                        subtitle: "สะสมจากยอดเปิดบ่อ + ขนเข้า − ร่อนออก"
                    ) {
                        LineChartView(
                            labels: chartLabels,
                            values: snapshot.series.map(\.remainingEndOfDay),
                            lineColor: accent,
                            primaryLabel: "คงเหลือ"
                        )
                    }
                }

                openingCard

                Text("คำนวณจากเที่ยวรถ (เข้าบ่อ) และร่อนทราย (ออกจากบ่อ) · หน่วยหลัก \(SandStockLogic.unitLabel) (ลูกบาศก์เมตร)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(AppTheme.spaceLG)
        }
        .background(DashboardBackground())
        .navigationTitle("สต๊อกทราย")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openingDraft = Self.draftString(SandStockLogic.loadOpeningCubic())
                    showOpeningEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("ตั้งค่ายอดเปิดบ่อ")
            }
        }
        .sheet(isPresented: $showOpeningEditor) {
            openingEditorSheet
        }
        .task(id: reloadToken) {
            await reload()
        }
        .onChange(of: appState.transactionsRevision) { _, _ in
            Task { await reload() }
        }
        .onChange(of: scope) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - Sections

    private var remainingHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("คงเหลือในบ่อสต๊อก", systemImage: "cylinder.split.1x2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.inkSecondary)
                Spacer()
                Text(scope.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fmt(max(0, snapshot.remainingCubic)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                Text(SandStockLogic.unitLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            Text("เฉลี่ยขนเข้า \(fmt(snapshot.avgDailyInCubic)) · ร่อนออก \(fmt(snapshot.avgDailyOutCubic)) \(SandStockLogic.unitLabel)/วัน")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var paceBanner: some View {
        let color = paceColor(snapshot.pace)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: paceIcon(snapshot.pace))
                    .foregroundStyle(color)
                Text("ขนมาจะทันไหม · \(snapshot.pace.title)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
            }
            Text(snapshot.insight)
                .font(.caption)
                .foregroundStyle(AppTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let days = snapshot.daysUntilEmpty {
                Text("ประมาณการหมดบ่อ ~\(fmt(days)) วัน (ถ้ารอบนี้คงที่)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private var openingCard: some View {
        Button {
            openingDraft = Self.draftString(SandStockLogic.loadOpeningCubic())
            showOpeningEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ยอดเปิดบ่อ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("\(fmt(snapshot.openingCubic)) \(SandStockLogic.unitLabel) · แตะเพื่อปรับ")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .fill(AppTheme.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private var openingEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ยอดเปิดบ่อ (คิว)", text: $openingDraft)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("ใช้เป็นจุดเริ่มก่อนรวมเที่ยวรถเข้าบ่อและร่อนทรายออกจากบ่อ เก็บเฉพาะเครื่องนี้")
                }
            }
            .navigationTitle("ยอดเปิดบ่อ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { showOpeningEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        let parsed = Double(
                            openingDraft
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: ",", with: "")
                        ) ?? 0
                        SandStockLogic.saveOpeningCubic(parsed)
                        showOpeningEditor = false
                        Task { await reload() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 8, y: 3)
        )
    }

    // MARK: - Data

    private var reloadToken: String {
        "\(scope.filter.start)-\(scope.filter.end)-\(appState.transactionsRevision)"
    }

    private var chartLabels: [String] {
        let labels = snapshot.series.map(\.label)
        if labels.count <= 10 { return labels }
        // Thin labels for denser ranges so the axis stays readable.
        return labels.enumerated().map { i, label in
            i == 0 || i == labels.count - 1 || i % max(labels.count / 6, 1) == 0 ? label : ""
        }
    }

    private func reload() async {
        let filter = scope.filter
        let txs = appState.transactions
        let opening = SandStockLogic.loadOpeningCubic()
        snapshot = await Task.detached(priority: .userInitiated) {
            SandStockLogic.build(filter: filter, transactions: txs, openingCubic: opening)
        }.value
    }

    // MARK: - Formatting helpers

    private func fmt(_ value: Double) -> String {
        DashboardAggregations.formatNumber(value)
    }

    private func signed(_ value: Double) -> String {
        let body = fmt(abs(value))
        if value > 0 { return "+\(body)" }
        if value < 0 { return "−\(body)" }
        return body
    }

    private func paceColor(_ pace: SandStockLogic.PaceStatus) -> Color {
        switch pace {
        case .keepingUp, .surplusBuilding: return AppTheme.income
        case .tight: return AppTheme.warning
        case .fallingBehind: return AppTheme.expense
        case .idle: return AppTheme.slate
        }
    }

    private func paceIcon(_ pace: SandStockLogic.PaceStatus) -> String {
        switch pace {
        case .keepingUp: return "checkmark.seal.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .fallingBehind: return "xmark.octagon.fill"
        case .surplusBuilding: return "arrow.up.circle.fill"
        case .idle: return "minus.circle.fill"
        }
    }

    private static func draftString(_ value: Double) -> String {
        if value == 0 { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
