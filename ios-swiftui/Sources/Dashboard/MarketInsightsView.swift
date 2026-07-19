import SwiftUI
import Charts

/// Fixed dark, high-tech palette for the Gold/Oil AI insights screen.
enum MarketPalette {
    static let page = Color(hex: "#05070D")
    static let panel = Color(hex: "#0C1220")
    static let card = Color(hex: "#111A2E")
    static let stroke = Color.white.opacity(0.08)
    static let textMuted = Color(hex: "#8A97AD")
    static let gold = Color(hex: "#F5C451")
    static let goldDeep = Color(hex: "#B8860B")
    static let oil = Color(hex: "#38BDF8")
    static let oilDeep = Color(hex: "#0369A1")
    static let up = Color(hex: "#34D399")
    static let down = Color(hex: "#F87171")
}

struct MarketInsightsView: View {
    let insight: MarketInsightSnapshot?
    let loading: Bool
    let error: String?
    let onRefresh: () async -> Void

    @State private var showGold = true
    @State private var showThai = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { showGold ? MarketPalette.gold : MarketPalette.oil }

    private var selectedKey: MarketAssetKey {
        switch (showGold, showThai) {
        case (true, true): return .thaiGold
        case (true, false): return .globalGold
        case (false, true): return .thaiFuel
        case (false, false): return .globalOil
        }
    }

    private var asset: MarketAsset? { insight?.payload.asset(selectedKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                assetSwitcher
                if let asset {
                    heroCard(asset)
                    probabilityAndForecast(asset)
                    if !asset.history.isEmpty { historyCard(asset) }
                    if !asset.metrics.isEmpty { metricsCard(asset) }
                    if !asset.aiSummary.isEmpty { aiCard(asset) }
                    if !asset.drivers.isEmpty { driversCard(asset) }
                    if !asset.news.isEmpty { newsCard(asset) }
                    disclaimer
                } else {
                    emptyOrError
                }
            }
            .padding(16)
        }
        .background(MarketPalette.page.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .scrollContentBackground(.hidden)
        .refreshable { await onRefresh() }
        .task { if insight == nil { await onRefresh() } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                    Text("AI MARKET INTELLIGENCE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                }
                .foregroundStyle(accent)

                Text("ทอง / น้ำมัน")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text(updatedLabel)
                    .font(.caption)
                    .foregroundStyle(MarketPalette.textMuted)
            }
            Spacer()
            Button {
                Task { await onRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(MarketPalette.stroke, lineWidth: 1))
            }
            .disabled(loading)
            .opacity(loading ? 0.5 : 1)
        }
    }

    private var updatedLabel: String {
        if loading { return "กำลังอัปเดต…" }
        guard let generatedAt = insight?.generatedAt, !generatedAt.isEmpty else {
            return "ยังไม่มีข้อมูลการวิเคราะห์"
        }
        return "อัปเดตล่าสุด: \(Self.friendlyDate(generatedAt))"
    }

    // MARK: - Switcher

    private var assetSwitcher: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                segButton(title: "ทองคำ", icon: "circle.hexagongrid.fill", active: showGold, tint: MarketPalette.gold) {
                    showGold = true
                }
                segButton(title: "น้ำมัน", icon: "fuelpump.fill", active: !showGold, tint: MarketPalette.oil) {
                    showGold = false
                }
            }
            HStack(spacing: 10) {
                regionChip(title: "ไทย", active: showThai) { showThai = true }
                regionChip(title: "ตลาดโลก", active: !showThai) { showThai = false }
            }
        }
    }

    private func segButton(title: String, icon: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(active ? Color.black : .white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active
                          ? LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(active ? Color.clear : MarketPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func regionChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(active ? .white : MarketPalette.textMuted)
                .background(
                    Capsule().fill(active ? accent.opacity(0.22) : Color.white.opacity(0.04))
                )
                .overlay(Capsule().stroke(active ? accent.opacity(0.5) : MarketPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero

    private func heroCard(_ asset: MarketAsset) -> some View {
        let dirColor = color(for: asset.direction)
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [accent.opacity(0.28), MarketPalette.panel, MarketPalette.panel],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(accent.opacity(0.25))
                .frame(width: 140, height: 140)
                .blur(radius: 24)
                .offset(x: 210, y: -50)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(asset.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    dataQualityBadge(asset.dataQuality)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.formatPrice(asset.currentPrice, currency: asset.currency))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(asset.currency + "/" + asset.unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MarketPalette.textMuted)
                }
                HStack(spacing: 8) {
                    Image(systemName: arrow(for: asset.direction))
                        .font(.caption.weight(.bold))
                    Text("\(Self.signed(asset.changeAbs, currency: asset.currency)) (\(Self.signedPct(asset.changePct)))")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(dirColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(dirColor.opacity(0.15)))
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MarketPalette.stroke, lineWidth: 1))
    }

    // MARK: - Probability + forecast

    private func probabilityAndForecast(_ asset: MarketAsset) -> some View {
        HStack(alignment: .top, spacing: 12) {
            probabilityGauge(asset)
            forecastPanel(asset)
        }
    }

    private func probabilityGauge(_ asset: MarketAsset) -> some View {
        let total = max(asset.probabilityUp + asset.probabilityDown, 0.0001)
        let upFraction = asset.probabilityUp / total
        return marketCard {
            VStack(spacing: 12) {
                Text("โอกาสทิศทาง")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MarketPalette.textMuted)
                ZStack {
                    Circle()
                        .stroke(MarketPalette.down.opacity(0.25), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(upFraction))
                        .stroke(
                            LinearGradient(
                                colors: [MarketPalette.up, MarketPalette.up.opacity(0.7)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(asset.probabilityUp.rounded()))%")
                            .font(.title2.bold())
                            .foregroundStyle(MarketPalette.up)
                        Text("ขึ้น")
                            .font(.caption2)
                            .foregroundStyle(MarketPalette.textMuted)
                    }
                }
                .frame(width: 120, height: 120)
                HStack {
                    Label("\(Int(asset.probabilityUp.rounded()))%", systemImage: "arrow.up")
                        .foregroundStyle(MarketPalette.up)
                    Spacer()
                    Label("\(Int(asset.probabilityDown.rounded()))%", systemImage: "arrow.down")
                        .foregroundStyle(MarketPalette.down)
                }
                .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func forecastPanel(_ asset: MarketAsset) -> some View {
        marketCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("คาดการณ์ (\(asset.forecast?.horizon ?? "รายวัน"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MarketPalette.textMuted)
                if let f = asset.forecast {
                    HStack(spacing: 8) {
                        Image(systemName: arrow(for: f.direction))
                        Text(Self.signedPct(f.expectedChangePct))
                            .font(.title3.bold())
                    }
                    .foregroundStyle(color(for: f.direction))

                    VStack(alignment: .leading, spacing: 6) {
                        forecastRow("ช่วงราคาคาด",
                                    "\(Self.formatPrice(f.expectedLow, currency: asset.currency)) – \(Self.formatPrice(f.expectedHigh, currency: asset.currency))")
                        forecastRow("ความเชื่อมั่น", "\(Int((f.confidence * 100).rounded()))%")
                    }
                    confidenceBar(f.confidence)
                } else {
                    Text("ไม่มีข้อมูลคาดการณ์")
                        .font(.caption)
                        .foregroundStyle(MarketPalette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func forecastRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(MarketPalette.textMuted)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
    }

    private func confidenceBar(_ confidence: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(max(confidence, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    // MARK: - History chart

    private func historyCard(_ asset: MarketAsset) -> some View {
        marketCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("ราคาย้อนหลัง")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Chart(asset.history) { point in
                    AreaMark(
                        x: .value("วันที่", point.date),
                        y: .value("ราคา", point.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("วันที่", point.date),
                        y: .value("ราคา", point.price)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel().foregroundStyle(MarketPalette.textMuted)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Metrics

    private func metricsCard(_ asset: MarketAsset) -> some View {
        marketCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ตัวชี้วัดประกอบการตัดสินใจ")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(asset.metrics) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(MarketPalette.textMuted)
                                .lineLimit(1)
                            Text(metric.value)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if let hint = metric.hint, !hint.isEmpty {
                                Text(hint)
                                    .font(.caption2)
                                    .foregroundStyle(MarketPalette.textMuted.opacity(0.8))
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
                    }
                }
            }
        }
    }

    // MARK: - AI summary

    private func aiCard(_ asset: MarketAsset) -> some View {
        marketCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(accent)
                    Text("บทวิเคราะห์ AI")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text(asset.aiSummary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Drivers

    private func driversCard(_ asset: MarketAsset) -> some View {
        marketCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("ปัจจัยหลัก")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                ForEach(Array(asset.drivers.enumerated()), id: \.offset) { _, driver in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(accent).frame(width: 6, height: 6).padding(.top, 6)
                        Text(driver)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - News

    private func newsCard(_ asset: MarketAsset) -> some View {
        marketCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ข่าวสำคัญ")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                ForEach(asset.news) { item in
                    newsRow(item)
                    if item.id != asset.news.last?.id {
                        Divider().overlay(MarketPalette.stroke)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func newsRow(_ item: MarketNewsItem) -> some View {
        let content = VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                sentimentBadge(item.sentiment)
                if !item.source.isEmpty {
                    Text(item.source)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MarketPalette.textMuted)
                }
                Spacer()
                if !item.publishedAt.isEmpty {
                    Text(item.publishedAt)
                        .font(.caption2)
                        .foregroundStyle(MarketPalette.textMuted)
                }
            }
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let url = URL(string: item.url), !item.url.isEmpty {
            Link(destination: url) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Disclaimer + states

    private var disclaimer: some View {
        Text(insight?.payload.disclaimer ?? "ข้อมูลนี้เป็นการวิเคราะห์เชิงสถิติ/AI ไม่ใช่คำแนะนำการลงทุน")
            .font(.caption2)
            .foregroundStyle(MarketPalette.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    private var emptyOrError: some View {
        marketCard {
            VStack(spacing: 12) {
                if loading {
                    ProgressView().tint(.white)
                    Text("กำลังโหลดการวิเคราะห์…")
                        .font(.subheadline)
                        .foregroundStyle(MarketPalette.textMuted)
                } else if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(MarketPalette.down)
                    Text("โหลดข้อมูลไม่สำเร็จ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(MarketPalette.textMuted)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(accent)
                    Text("ยังไม่มีข้อมูลการวิเคราะห์")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("ระบบจะวิเคราะห์ราคาทอง/น้ำมันด้วย AI แบบรายวัน กดรีเฟรชเพื่อดึงผลล่าสุด")
                        .font(.caption)
                        .foregroundStyle(MarketPalette.textMuted)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await onRefresh() }
                } label: {
                    Text("รีเฟรช")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(accent))
                }
                .disabled(loading)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Small helpers

    private func dataQualityBadge(_ quality: MarketDataQuality) -> some View {
        let (label, color): (String, Color) = {
            switch quality {
            case .high: return ("ข้อมูลแม่นยำ", MarketPalette.up)
            case .medium: return ("ข้อมูลประเมิน", MarketPalette.gold)
            case .low: return ("ข้อมูลจำกัด", MarketPalette.down)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func sentimentBadge(_ sentiment: MarketSentiment) -> some View {
        let (label, color): (String, Color) = {
            switch sentiment {
            case .positive: return ("บวก", MarketPalette.up)
            case .negative: return ("ลบ", MarketPalette.down)
            case .neutral: return ("กลาง", MarketPalette.textMuted)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func marketCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MarketPalette.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MarketPalette.stroke, lineWidth: 1))
    }

    private func color(for direction: MarketDirection) -> Color {
        switch direction {
        case .up: return MarketPalette.up
        case .down: return MarketPalette.down
        case .flat: return MarketPalette.textMuted
        }
    }

    private func arrow(for direction: MarketDirection) -> String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    // MARK: - Formatting

    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    static func formatPrice(_ value: Double, currency: String) -> String {
        let decimals = value >= 1000 ? 0 : 2
        priceFormatter.minimumFractionDigits = decimals
        priceFormatter.maximumFractionDigits = decimals
        return priceFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func signed(_ value: Double, currency: String) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        return sign + formatPrice(abs(value), currency: currency)
    }

    static func signedPct(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "" : "")
        return String(format: "%@%.2f%%", sign, value)
    }

    static func friendlyDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "th_TH")
        out.timeZone = TimeZone(identifier: "Asia/Bangkok")
        out.dateFormat = "d MMM yyyy HH:mm น."
        return out.string(from: date)
    }
}
