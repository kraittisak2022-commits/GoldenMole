import Charts
import SwiftUI

enum AppTheme {
    // MARK: Brand
    static let brand = Color(hex: "#0D98A5")
    static let brandDark = Color(hex: "#063A40")
    static let brandMid = Color(hex: "#0A6B75")
    static let brandSoft = Color(hex: "#E6F7F8")

    // MARK: Semantic
    static let income = Color(hex: "#10b981")
    static let expense = Color(hex: "#ef4444")
    static let warning = Color(hex: "#f59e0b")
    static let info = Color(hex: "#3b82f6")
    static let purple = Color(hex: "#8b5cf6")
    static let slate = Color(hex: "#64748b")
    static let cyan = Color(hex: "#22D3EE")

    // MARK: Categories
    static let labor = Color(hex: "#10b981")
    static let vehicle = Color(hex: "#f59e0b")
    static let fuel = Color(hex: "#ea580c")
    static let maintenance = Color(hex: "#64748b")
    static let land = Color(hex: "#8b5cf6")
    static let sand = Color(hex: "#ec4899")
    static let dailyLog = Color(hex: "#06b6d4")

    // MARK: Premium surfaces (adaptive light / dark)
    static let pageTop = Color(light: Color(hex: "#F5F8FC"), dark: Color(hex: "#070B16"))
    static let pageBottom = Color(light: Color(hex: "#EAF0F8"), dark: Color(hex: "#0B1020"))
    static let surface = Color(light: Color.white, dark: Color(hex: "#131B2D"))
    static let surfaceSoft = Color(light: Color(hex: "#F1F5F9"), dark: Color(hex: "#1A2438"))
    static let hairline = Color(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.08))
    static let ink = Color(light: Color(hex: "#0F172A"), dark: Color(hex: "#F8FAFC"))
    static let inkSecondary = Color(light: Color(hex: "#334155"), dark: Color(hex: "#CBD5E1"))
    static let inkMuted = Color(light: Color(hex: "#64748B"), dark: Color(hex: "#94A3B8"))
    static let cardShadow = Color(light: Color.black.opacity(0.06), dark: Color.black.opacity(0.45))
    static let glow = Color(light: Color(hex: "#22D3EE").opacity(0.12), dark: Color(hex: "#22D3EE").opacity(0.22))

    // MARK: Spacing
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 16
    static let spaceXL: CGFloat = 24

    // MARK: Radius
    static let radiusSM: CGFloat = 12
    static let radiusMD: CGFloat = 16
    static let radiusLG: CGFloat = 20
    static let radiusXL: CGFloat = 24

    static func categoryColor(for key: String) -> Color {
        switch key.lowercased() {
        case "labor": return labor
        case "vehicle": return vehicle
        case "fuel": return fuel
        case "maintenance": return maintenance
        case "land": return land
        case "sand", "dailylog": return sand
        case "income": return income
        default: return info
        }
    }
}

// MARK: - Appearance mode

/// User-selectable app appearance, persisted via @AppStorage("appearanceMode").
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "ตามระบบ"
        case .light: return "สว่าง"
        case .dark: return "มืด"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

// MARK: - Premium page background

struct DashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.pageTop, AppTheme.pageBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            // Soft top glow — stronger in dark mode (NEXUS-style).
            RadialGradient(
                colors: [
                    (colorScheme == .dark ? AppTheme.cyan : AppTheme.brand).opacity(colorScheme == .dark ? 0.18 : 0.08),
                    .clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 380
            )
            .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Section card

struct SectionCard<Content: View>: View {
    let title: String?
    var systemImage: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            if let title {
                SectionHeader(title: title, systemImage: systemImage, subtitle: subtitle)
            }
            content()
        }
        .padding(AppTheme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }
}

// MARK: - KPI tile

struct KPITile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var accent: Color = AppTheme.brand
    var systemImage: String = "chart.bar.fill"
    /// Optional sparkline series (defaults keep existing call sites working).
    var trend: [Double]? = nil
    /// Optional delta chip text, e.g. "+12.4%". Color inferred from leading +/- when present.
    var deltaText: String? = nil

    private var deltaPositive: Bool? {
        guard let deltaText, let first = deltaText.first else { return nil }
        if first == "+" || first == "▲" { return true }
        if first == "-" || first == "▼" { return false }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .shadow(color: accent.opacity(0.35), radius: 6, y: 2)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let deltaText {
                    Text(deltaText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(deltaChipForeground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(deltaChipBackground))
                }
            }
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let trend, trend.count >= 2 {
                Chart(Array(trend.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("i", item.offset),
                        y: .value("v", item.element)
                    )
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("i", item.offset),
                        y: .value("v", item.element)
                    )
                    .foregroundStyle(accent.opacity(0.18))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 28)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(2)
            }
            Capsule()
                .fill(accent)
                .frame(height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var deltaChipForeground: Color {
        switch deltaPositive {
        case true: return AppTheme.income
        case false: return AppTheme.expense
        case nil: return AppTheme.inkMuted
        }
    }

    private var deltaChipBackground: Color {
        switch deltaPositive {
        case true: return AppTheme.income.opacity(0.15)
        case false: return AppTheme.expense.opacity(0.15)
        case nil: return AppTheme.surface.opacity(0.6)
        }
    }
}

// MARK: - KPI strip card (horizontal snapping strip)

struct KPIStripCard: View {
    let title: String
    let value: String
    var accent: Color = AppTheme.brand
    var systemImage: String = "chart.bar.fill"
    var trend: [Double]? = nil
    var deltaText: String? = nil

    private var deltaPositive: Bool? {
        guard let deltaText, let first = deltaText.first else { return nil }
        if first == "+" || first == "▲" { return true }
        if first == "-" || first == "▼" { return false }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Spacer(minLength: 0)
                if let deltaText {
                    Text(deltaText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(deltaChipForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(deltaChipBackground, in: Capsule())
                }
            }

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let trend, trend.count >= 2 {
                Chart {
                    ForEach(Array(trend.enumerated()), id: \.offset) { index, point in
                        LineMark(
                            x: .value("i", index),
                            y: .value("v", point)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accent)
                        AreaMark(
                            x: .value("i", index),
                            y: .value("v", point)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accent.opacity(0.18))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 28)
            }
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow, radius: 8, y: 3)
    }

    private var deltaChipForeground: Color {
        switch deltaPositive {
        case true: return AppTheme.income
        case false: return AppTheme.expense
        case nil: return AppTheme.inkMuted
        }
    }

    private var deltaChipBackground: Color {
        switch deltaPositive {
        case true: return AppTheme.income.opacity(0.15)
        case false: return AppTheme.expense.opacity(0.15)
        case nil: return AppTheme.surfaceSoft
        }
    }
}

// MARK: - Pill badge

struct PillBadge: View {
    let text: String
    var color: Color = AppTheme.brand

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.inkMuted)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Date filter bar

struct DateFilterBar: View {
    @Binding var datePreset: DateRangePreset
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(AppTheme.brand)
                Picker("ช่วงวันที่", selection: $datePreset) {
                    ForEach(DateRangePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            if datePreset == .custom {
                HStack {
                    DatePicker("เริ่ม", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                    Text("–")
                        .foregroundStyle(AppTheme.inkMuted)
                    DatePicker("สิ้นสุด", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceSoft.opacity(0.85))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: 1)
        }
    }
}
