import SwiftUI

/// Live sand-stock pond board — game-style HUD with realtime fill + feed.
struct SandStockHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var focusDate = Date()
    @State private var showDatePicker = false
    @State private var snapshot = SandStockLogic.Snapshot.empty
    @State private var openingDraft = ""
    @State private var capacityDraft = ""
    @State private var showSettingsEditor = false
    @State private var livePing = false
    @State private var boardPulse = false
    @State private var displayedFill: CGFloat = 0
    @State private var lastRevision: Int = -1

    private var accent: Color { AppTheme.sand }
    private let liveGreen = Color(hex: "#10B981")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                liveHeader

                pondHero
                    .scaleEffect(boardPulse && !reduceMotion ? 1.015 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: boardPulse)

                hudRow

                paceBanner

                liveFeedSection

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
                        subtitle: "สะสมจาก 4 ส.ค. 2569 · ยอดเปิดบ่อ + ขนเข้า − ร่อนออก"
                    ) {
                        LineChartView(
                            labels: chartLabels,
                            values: snapshot.series.map(\.remainingEndOfDay),
                            lineColor: accent,
                            primaryLabel: "คงเหลือ"
                        )
                    }
                }

                settingsCard

                Text("อัปเดตจากซิงก์เรียลไทม์ · หน่วยหลัก \(SandStockLogic.unitLabel) (ลูกบาศก์เมตร)")
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
                    capacityDraft = Self.draftString(SandStockLogic.loadPondCapacityCubic())
                    showSettingsEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("ตั้งค่าบ่อสต๊อก")
            }
        }
        .sheet(isPresented: $showSettingsEditor) {
            settingsEditorSheet
        }
        .sheet(isPresented: $showDatePicker) {
            RealtimeFocusCalendarSheet(
                selection: $focusDate,
                transactions: appState.transactions,
                employees: appState.employees,
                transactionsRevision: appState.transactionsRevision,
                onDismiss: { showDatePicker = false }
            )
        }
        .task {
            startLivePing()
            await reload(animate: false)
        }
        .onChange(of: reloadToken) { _, _ in
            Task { await reload(animate: true) }
        }
    }

    // MARK: - LIVE header

    private var focusDateStr: String { DashboardAggregations.formatYMD(focusDate) }
    private var isToday: Bool { focusDateStr == DashboardAggregations.todayYMD() }

    private var chartFilter: DateFilter {
        let end = focusDateStr
        let start = DashboardAggregations.shiftDateStr(end, deltaDays: -6)
        let earliest = DashboardAggregations.shiftDateStr(DashboardAggregations.todayYMD(), deltaDays: -90)
        return DateFilter(start: max(start, earliest), end: end)
    }

    private var liveHeader: some View {
        HStack(spacing: 10) {
            liveBadge
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("บ่อสต๊อกสด")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        HStack(spacing: 6) {
                            Text(thaiDateShort(focusDateStr))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.inkMuted)
                            if isToday {
                                Text("วันนี้")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(liveGreen)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(liveGreen.opacity(0.14)))
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เลือกวันที่กำลังดู")
            .accessibilityHint("แตะเพื่อเลือกวันย้อนหลัง")

            if !isToday {
                Button {
                    focusDate = Date()
                } label: {
                    Text("กลับวันนี้")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Text("\(fmt(snapshot.pondCapacityCubic)) \(SandStockLogic.unitLabel)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.surfaceSoft))
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                if !reduceMotion && livePing {
                    Circle()
                        .fill(liveGreen.opacity(boardPulse ? 0.55 : 0.28))
                        .frame(width: 12, height: 12)
                }
                Circle()
                    .fill(liveGreen)
                    .frame(width: 8, height: 8)
            }
            Text("LIVE")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundStyle(Color(hex: "#6EE7B7"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(liveGreen.opacity(0.15)))
        .overlay(Capsule().strokeBorder(liveGreen.opacity(boardPulse ? 0.7 : 0.35)))
    }

    // MARK: - Pond hero

    private var pondHero: some View {
        VStack(spacing: 14) {
            HStack {
                Label("คงเหลือในบ่อ", systemImage: "cylinder.split.1x2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.inkSecondary)
                Spacer()
                Text("\(Int((snapshot.fillRatio * 100).rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#1C1917").opacity(0.92),
                                Color(hex: "#292524")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(accent.opacity(0.35), lineWidth: 2)
                    )

                GeometryReader { geo in
                    let fillH = max(8, geo.size.height * displayedFill)
                    ZStack(alignment: .bottom) {
                        // Sand body
                        UnevenRoundedRectangle(
                            topLeadingRadius: displayedFill > 0.92 ? 24 : 10,
                            bottomLeadingRadius: 24,
                            bottomTrailingRadius: 24,
                            topTrailingRadius: displayedFill > 0.92 ? 24 : 10,
                            style: .continuous
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#F9A8D4"),
                                    accent,
                                    Color(hex: "#9D174D")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: fillH)
                        .overlay(alignment: .top) {
                            if displayedFill > 0.04 {
                                Capsule()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(height: 6)
                                    .padding(.horizontal, 18)
                                    .offset(y: -2)
                            }
                        }

                        // Center score readout
                        VStack(spacing: 2) {
                            Text(fmt(max(0, snapshot.remainingCubic)))
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: snapshot.remainingCubic)
                            Text(SandStockLogic.unitLabel)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(10)
                }
                .frame(height: 220)
            }

            Text("เฉลี่ยขนเข้า \(fmt(snapshot.avgDailyInCubic)) · ร่อนออก \(fmt(snapshot.avgDailyOutCubic)) \(SandStockLogic.unitLabel)/วัน")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 12, y: 5)
        )
    }

    // MARK: - HUD

    private var hudRow: some View {
        let dayNet = snapshot.priorRemainingCubic + snapshot.todayInCubic - snapshot.todayOutCubic
        return HStack(spacing: 10) {
            hudChip(
                title: "ขนเข้า",
                value: "+\(fmt(snapshot.todayInCubic))",
                color: AppTheme.income,
                icon: "arrow.down.to.line"
            )
            hudChip(
                title: "ร่อนออก",
                value: "−\(fmt(snapshot.todayOutCubic))",
                color: AppTheme.expense,
                icon: "arrow.up.right"
            )
            hudChip(
                title: "สุทธิ",
                value: signed(dayNet),
                color: dayNet >= 0 ? AppTheme.income : AppTheme.warning,
                icon: "arrow.left.arrow.right"
            )
        }
    }

    private func hudChip(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(SandStockLogic.unitLabel)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Pace

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

    // MARK: - Live feed

    private var liveFeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("เหตุการณ์ล่าสุด")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(isToday ? "วันนี้" : thaiDateShort(focusDateStr))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            if snapshot.recentEvents.isEmpty {
                Text(isToday ? "ยังไม่มีเที่ยวเข้าหรือร่อนออกในวันนี้" : "ยังไม่มีเที่ยวเข้าหรือร่อนออกในวันที่เลือก")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(snapshot.recentEvents) { event in
                    feedRow(event)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
    }

    private func feedRow(_ event: SandStockLogic.FeedEvent) -> some View {
        let inbound = event.direction == .inbound
        let color = inbound ? AppTheme.income : AppTheme.expense
        return HStack(spacing: 10) {
            Image(systemName: inbound ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.direction.title) · \(event.label)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(event.timeLabel)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
            Text("\(inbound ? "+" : "−")\(fmt(event.cubic)) \(SandStockLogic.unitLabel)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Settings

    private var settingsCard: some View {
        Button {
            openingDraft = Self.draftString(SandStockLogic.loadOpeningCubic())
            capacityDraft = Self.draftString(SandStockLogic.loadPondCapacityCubic())
            showSettingsEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ตั้งค่าบ่อ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("เปิด \(fmt(snapshot.openingCubic)) · จุ \(fmt(snapshot.pondCapacityCubic)) \(SandStockLogic.unitLabel)")
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

    private var settingsEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ยอดเปิดบ่อ (คิว)", text: $openingDraft)
                        .keyboardType(.decimalPad)
                    TextField("ความจุบ่อ (คิว)", text: $capacityDraft)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("ยอดเปิดใช้เป็นจุดเริ่มก่อนรวมเที่ยวเข้า/ร่อนออก ความจุใช้แสดงระดับบ่อแบบเกม เก็บเฉพาะเครื่องนี้")
                }
            }
            .navigationTitle("ตั้งค่าบ่อสต๊อก")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { showSettingsEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        SandStockLogic.saveOpeningCubic(parseDraft(openingDraft))
                        let capacity = parseDraft(capacityDraft)
                        SandStockLogic.savePondCapacityCubic(
                            capacity > 0 ? capacity : SandStockLogic.defaultPondCapacityCubic
                        )
                        showSettingsEditor = false
                        Task { await reload(animate: true) }
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
        "\(chartFilter.start)-\(chartFilter.end)-\(appState.transactionsRevision)"
    }

    private var chartLabels: [String] {
        let labels = snapshot.series.map(\.label)
        if labels.count <= 10 { return labels }
        return labels.enumerated().map { i, label in
            i == 0 || i == labels.count - 1 || i % max(labels.count / 6, 1) == 0 ? label : ""
        }
    }

    private func reload(animate: Bool) async {
        let filter = chartFilter
        let txs = appState.transactions
        let opening = SandStockLogic.loadOpeningCubic()
        let capacity = SandStockLogic.loadPondCapacityCubic()
        let revision = appState.transactionsRevision
        let next = await Task.detached(priority: .userInitiated) {
            SandStockLogic.build(
                filter: filter,
                transactions: txs,
                openingCubic: opening,
                pondCapacityCubic: capacity
            )
        }.value

        let shouldPulse = animate && lastRevision >= 0 && revision != lastRevision
        lastRevision = revision

        if animate && !reduceMotion {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                snapshot = next
                displayedFill = CGFloat(next.fillRatio)
            }
            if shouldPulse { triggerPulse() }
        } else {
            snapshot = next
            displayedFill = CGFloat(next.fillRatio)
        }
    }

    private func triggerPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.2)) { boardPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.25)) { boardPulse = false }
        }
    }

    private func startLivePing() {
        guard !reduceMotion else { return }
        livePing = true
    }

    // MARK: - Formatting helpers

    private func thaiDateShort(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return ymd }
        return String(format: "%02d/%02d/%04d", parts[2], parts[1], parts[0])
    }

    private func fmt(_ value: Double) -> String {
        DashboardAggregations.formatNumber(value)
    }

    private func signed(_ value: Double) -> String {
        let body = fmt(abs(value))
        if value > 0 { return "+\(body)" }
        if value < 0 { return "−\(body)" }
        return body
    }

    private func parseDraft(_ text: String) -> Double {
        Double(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
        ) ?? 0
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
