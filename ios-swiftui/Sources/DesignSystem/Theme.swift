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

    // MARK: Categories
    static let labor = Color(hex: "#10b981")
    static let vehicle = Color(hex: "#f59e0b")
    static let fuel = Color(hex: "#ea580c")
    static let maintenance = Color(hex: "#64748b")
    static let land = Color(hex: "#8b5cf6")
    static let sand = Color(hex: "#ec4899")
    static let dailyLog = Color(hex: "#06b6d4")

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
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
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
                    .foregroundStyle(.primary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                .fill(Color(.secondarySystemBackground))
        )
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
            .background(color.opacity(0.12), in: Capsule())
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
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    DatePicker("สิ้นสุด", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground).opacity(0.65))
    }
}
