import SwiftUI

// MARK: - Home Motion & Tactile Feedback System

/// Tactile Apple-style spring press feedback for cards, tiles, and interactive rows.
struct HomeTactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.22, bounce: 0.15),
                value: configuration.isPressed
            )
    }
}

/// Subtle staggered spring entrance for Home sections.
struct HomeSectionAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.985)
            .onAppear {
                guard !appeared else { return }
                let delay = reduceMotion ? 0 : Double(min(index, 6)) * 0.038
                let anim: Animation = reduceMotion
                    ? .easeOut(duration: 0.18)
                    : .spring(duration: 0.44, bounce: 0.12).delay(delay)
                withAnimation(anim) {
                    appeared = true
                }
            }
    }
}

extension View {
    func homeAppear(index: Int) -> some View {
        modifier(HomeSectionAppear(index: index))
    }
}

/// Living radar pulse dot for real-time sync or urgent indicators (iOS 17 PhaseAnimator).
struct HomeLivePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = AppTheme.income
    var size: CGFloat = 6

    var body: some View {
        ZStack {
            if !reduceMotion {
                PhaseAnimator([false, true]) { expanded in
                    Circle()
                        .fill(color.opacity(expanded ? 0 : 0.42))
                        .frame(width: size, height: size)
                        .scaleEffect(expanded ? 2.4 : 1.0)
                } animation: { expanded in
                    expanded ? .easeOut(duration: 1.5) : .linear(duration: 0.01)
                }
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.2, height: size * 2.2)
    }
}

/// Soft diagonal shimmer sweep for cold-load Home skeletons.
struct HomeShimmerOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.28),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: active ? geo.size.width * 1.2 : -geo.size.width * 0.7)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: false)) {
                            active = true
                        }
                    }
                }
            }
    }
}

/// Sleek cold-launch skeleton matching the Home Executive layout.
struct HomeOverviewSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.surfaceSoft)
                    .frame(height: 188)
                    .modifier(HomeShimmerOverlay())

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surface)
                    .frame(height: 152)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    )
                    .modifier(HomeShimmerOverlay())

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surface)
                    .frame(height: 170)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    )
                    .modifier(HomeShimmerOverlay())

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.surface)
                        .frame(height: 108)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppTheme.hairline, lineWidth: 1)
                        )
                        .modifier(HomeShimmerOverlay())
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.surface)
                        .frame(height: 108)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppTheme.hairline, lineWidth: 1)
                        )
                        .modifier(HomeShimmerOverlay())
                }
            }
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.top, 10)
            .padding(.bottom, AppTheme.spaceXL)
        }
        .scrollContentBackground(.hidden)
        .accessibilityLabel("กำลังเตรียมหน้าแรก")
    }
}

// MARK: - Unified Home Card Surface

struct HomeCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 18
    var borderColor: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.surface)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.black.opacity(0.32)
                            : Color.black.opacity(0.045),
                        radius: colorScheme == .dark ? 10 : 12,
                        y: colorScheme == .dark ? 4 : 3
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor ?? AppTheme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func homeCardSurface(cornerRadius: CGFloat = 18, borderColor: Color? = nil) -> some View {
        modifier(HomeCardSurface(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

// MARK: - Section Header

struct HomeSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 0)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Adaptive Semantic Delta Colors

enum HomeSemanticColor {
    static let positiveText = Color(light: Color(hex: "#15803D"), dark: Color(hex: "#4ADE80"))
    static let positiveFill = Color(light: Color(hex: "#15803D").opacity(0.11), dark: Color(hex: "#4ADE80").opacity(0.15))
    static let negativeText = Color(light: Color(hex: "#B91C1C"), dark: Color(hex: "#F87171"))
    static let negativeFill = Color(light: Color(hex: "#B91C1C").opacity(0.11), dark: Color(hex: "#F87171").opacity(0.15))
    static let tealAccent = Color(light: Color(hex: "#0F766E"), dark: Color(hex: "#2DD4BF"))
}

// MARK: - Delta Badge

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
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(good ? HomeSemanticColor.positiveText : HomeSemanticColor.negativeText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(good ? HomeSemanticColor.positiveFill : HomeSemanticColor.negativeFill)
            )
            .accessibilityLabel(label)
        }
    }
}

// MARK: - Executive Hero

struct HomeProCommandHero: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let greetingName: String
    let dayTitle: String
    let pro: HomeProSnapshot
    let laborBahtLabel: String
    var presentCount: Int = 0

    @State private var auraDrift = false

    private var heroGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(hex: "#061E24"), Color(hex: "#0A3640"), Color(hex: "#0E4B57")]
            : [Color(hex: "#052B32"), Color(hex: "#0A4E59"), Color(hex: "#0D737F")]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var timeGreeting: (text: String, icon: String) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return ("สวัสดีตอนเช้า", "sun.horizon.fill")
        case 12..<17: return ("สวัสดีตอนบ่าย", "sun.max.fill")
        case 17..<21: return ("สวัสดีตอนเย็น", "sunset.fill")
        default: return ("สวัสดีตอนค่ำ", "moon.stars.fill")
        }
    }

    private var firstMissingItem: HomeProSnapshot.ChecklistItem? {
        pro.checklist.first { !$0.isDone }
    }

    private var missingSummary: String {
        pro.checklist.filter { !$0.isDone }.map(\.title).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            kpiStrip
            statusFooter
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                heroGradient

                Circle()
                    .fill(AppTheme.cyan.opacity(colorScheme == .dark ? 0.14 : 0.17))
                    .frame(width: 190, height: 190)
                    .blur(radius: 44)
                    .offset(
                        x: auraDrift ? 42 : 66,
                        y: auraDrift ? -54 : -72
                    )
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color(hex: "#34D399").opacity(colorScheme == .dark ? 0.08 : 0.10))
                    .frame(width: 120, height: 120)
                    .blur(radius: 36)
                    .offset(
                        x: auraDrift ? -210 : -180,
                        y: auraDrift ? 120 : 140
                    )
                    .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color(hex: "#062D34").opacity(colorScheme == .dark ? 0.45 : 0.22),
            radius: 16,
            y: 6
        )
        .onAppear {
            guard !reduceMotion, !auraDrift else { return }
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                auraDrift = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: timeGreeting.icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "#FDE68A").opacity(0.92))
                    Text(timeGreeting.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                }

                Text(greetingName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(dayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            completionRing
        }
    }

    private var completionRing: some View {
        let isStrong = pro.health == .strong
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: CGFloat(pro.completion))
                    .stroke(
                        isStrong ? Color(hex: "#6EE7B7") : Color.white,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        reduceMotion ? .none : .spring(duration: 0.55, bounce: 0.18),
                        value: pro.completion
                    )
                if isStrong {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color(hex: "#6EE7B7"))
                        .symbolEffect(.bounce, value: isStrong)
                        .symbolEffectsRemoved(reduceMotion)
                } else {
                    Text("\(pro.coreCompleted)/\(pro.coreTotal)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.3), value: pro.coreCompleted)
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(isStrong ? "ครบถ้วน" : "ความคืบหน้า")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
                Text(statusShortText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isStrong ? Color(hex: "#A7F3D0") : Color(hex: "#FDE68A"))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: pro.coreCompleted)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.11))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pro.health.label) \(pro.coreCompleted) จาก \(pro.coreTotal) รายการ")
    }

    private var statusShortText: String {
        let remaining = max(0, pro.coreTotal - pro.coreCompleted)
        if remaining == 0 { return "ครบ \(pro.coreTotal) งาน" }
        return "ขาด \(remaining) งาน"
    }

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            NavigationLink {
                TodayOpsDetailScreen(kind: .trips)
            } label: {
                heroMetricCell(
                    title: "เที่ยวรถ",
                    value: "\(Int(pro.trip.current))",
                    numericKey: pro.trip.current,
                    unit: "เที่ยว",
                    delta: pro.trip
                )
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))

            heroDivider

            NavigationLink {
                TodayOpsDetailScreen(kind: .sand)
            } label: {
                heroMetricCell(
                    title: "ร่อนทราย",
                    value: "\(Int(pro.sand.current))",
                    numericKey: pro.sand.current,
                    unit: "รอบ",
                    delta: pro.sand
                )
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))

            heroDivider

            NavigationLink {
                CategoryReportScreen(type: .labor)
            } label: {
                heroMetricCell(
                    title: "ค่าแรง",
                    value: shortMoney(pro.labor.current),
                    numericKey: pro.labor.current,
                    unit: nil,
                    delta: pro.labor,
                    upIsGood: false
                )
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 38)
    }

    private func heroMetricCell(
        title: String,
        value: String,
        numericKey: Double,
        unit: String?,
        delta: HomeProSnapshot.MetricDelta,
        upIsGood: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: numericKey)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }
            }

            if let shortDelta = shortDeltaLabel(delta) {
                let good = upIsGood ? delta.isUp : !delta.isUp
                Text(shortDelta)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(good ? Color(hex: "#A7F3D0") : Color(hex: "#FECACA"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text("—")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let missing = firstMissingItem, pro.health != .strong {
            NavigationLink {
                HomeChecklistRouterView(destination: missing.destination)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#FCD34D"))
                        .frame(width: 7, height: 7)
                    Text("ยังขาด: \(missingSummary.isEmpty ? missing.title : missingSummary)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        Text("บันทึก")
                            .font(.caption2.weight(.bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: "#FDE68A"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.98))
            .accessibilityLabel("ยังขาด \(missingSummary) แตะเพื่อไปบันทึก\(missing.title)")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#6EE7B7"))
                Text(completeFooterText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.16))
            )
        }
    }

    private var completeFooterText: String {
        if presentCount > 0 {
            return "บันทึกงานหลักครบแล้ว · มาทำงาน \(presentCount) คน"
        }
        return laborBahtLabel.isEmpty ? "บันทึกงานหลักครบแล้ว" : laborBahtLabel
    }

    private func shortDeltaLabel(_ delta: HomeProSnapshot.MetricDelta) -> String? {
        if let pct = delta.vsYesterdayPct, delta.yesterday > 0 || delta.current > 0 {
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(Int(pct.rounded()))% เมื่อวาน"
        }
        if let pct = delta.vsAvg7Pct, delta.avg7 > 0 {
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(Int(pct.rounded()))% เฉลี่ย"
        }
        return nil
    }

    private func shortMoney(_ value: Double) -> String {
        if value <= 0 { return "฿0" }
        if value >= 1000 {
            return "฿\(DashboardAggregations.formatNumber(value / 1000))k"
        }
        return DashboardAggregations.formatCurrency(value)
    }
}

// MARK: - Checklist Destination Router

struct HomeChecklistRouterView: View {
    let destination: HomeProSnapshot.ChecklistDestination

    var body: some View {
        switch destination {
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

// MARK: - Smart Compact Checklist

struct HomeProChecklistCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pro: HomeProSnapshot

    @State private var expandedWhenComplete = false

    private var isComplete: Bool { pro.health == .strong }
    private var showsGrid: Bool { !isComplete || expandedWhenComplete }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        if !pro.checklist.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if showsGrid {
                    segmentedProgressBar

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(pro.checklist) { item in
                            checklistTile(item)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .padding(16)
            .homeCardSurface()
            .sensoryFeedback(.selection, trigger: expandedWhenComplete)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "checklist")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
                .symbolEffect(.bounce, value: pro.coreCompleted)
                .symbolEffectsRemoved(reduceMotion)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(statusColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(isComplete ? "งานหลักวันนี้ครบถ้วน" : "ความคืบหน้าบันทึกวันนี้")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                if isComplete && !expandedWhenComplete {
                    Text("ครบทั้ง \(pro.coreTotal) รายการ · แตะเพื่อตรวจสอบ")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }

            Spacer(minLength: 0)

            Text("\(pro.coreCompleted)/\(pro.coreTotal)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(statusColor.opacity(0.12)))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: pro.coreCompleted)

            if isComplete {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.28)) {
                        expandedWhenComplete.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                        .rotationEffect(.degrees(expandedWhenComplete ? 180 : 0))
                        .animation(reduceMotion ? .none : .snappy(duration: 0.28), value: expandedWhenComplete)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.surfaceSoft))
                }
                .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(expandedWhenComplete ? "ย่อรายการความคืบหน้า" : "ดูรายการความคืบหน้า")
            }
        }
    }

    private var segmentedProgressBar: some View {
        HStack(spacing: 5) {
            ForEach(pro.checklist) { item in
                Capsule()
                    .fill(item.isDone ? AppTheme.income : AppTheme.surfaceSoft)
                    .frame(height: 5)
                    .animation(
                        reduceMotion ? .none : .spring(duration: 0.4, bounce: 0.2),
                        value: item.isDone
                    )
            }
        }
        .accessibilityLabel("ครบ \(pro.coreCompleted) จาก \(pro.coreTotal) รายการ")
    }

    private var statusColor: Color {
        switch pro.health {
        case .strong: return AppTheme.income
        case .attention: return AppTheme.warning
        case .critical: return AppTheme.expense
        }
    }

    private func checklistTile(_ item: HomeProSnapshot.ChecklistItem) -> some View {
        let accent = Color(hex: item.accentHex)
        return NavigationLink {
            HomeChecklistRouterView(destination: item.destination)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : item.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.isDone ? AppTheme.income : accent)
                    Spacer(minLength: 0)
                    if !item.isDone {
                        Circle()
                            .fill(AppTheme.warning)
                            .frame(width: 6, height: 6)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.inkMuted.opacity(0.75))
                }

                Text(item.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Text(item.isDone ? item.detail : "ยังไม่บันทึก")
                    .font(.caption2.weight(item.isDone ? .medium : .semibold))
                    .foregroundStyle(item.isDone ? AppTheme.inkMuted : AppTheme.warning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppTheme.surfaceSoft.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        item.isDone ? AppTheme.hairline : AppTheme.warning.opacity(0.32),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
        .accessibilityLabel("\(item.title) \(item.isDone ? "บันทึกแล้ว \(item.detail)" : "ยังไม่บันทึก")")
    }
}

// MARK: - Quiet Signals Strip (Non-Redundant)

struct HomeProInsightStrip: View {
    let insights: [String]
    let alerts: [OverviewAlert]

    /// Drop completion status already surfaced in the Hero + Checklist right above.
    private var actionableAlerts: [OverviewAlert] {
        alerts.filter { $0.id != "home_health" }
    }

    private var actionableInsights: [String] {
        insights.filter { line in
            !line.hasPrefix("ยังไม่บันทึก ")
                && !line.contains("ค่อนข้างนิ่ง")
        }
    }

    var body: some View {
        if !actionableAlerts.isEmpty || !actionableInsights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.brand)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.brand.opacity(0.12))
                        )
                    Text("สัญญาณที่ควรติดตาม")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                }

                if !actionableAlerts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(actionableAlerts) { alert in
                                alertChip(alert)
                            }
                        }
                    }
                }

                if !actionableInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(actionableInsights.prefix(2).enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(AppTheme.brand.opacity(0.75))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .homeCardSurface()
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
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(alert.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}
