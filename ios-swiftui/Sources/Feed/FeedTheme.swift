import SwiftUI

// MARK: - Crisp Facebook White Theme Palette

/// Dedicated crisp white social-feed palette (Facebook iOS aesthetic) — intentionally
/// light and clean so the อัพเดตงาน feed always reads like a bright social media stream.
enum FeedPalette {
    static let canvas = Color(hex: "#F0F2F5")
    static let card = Color.white
    static let surfaceMuted = Color(hex: "#F0F2F5")
    static let surfaceSubtle = Color(hex: "#F7F8FA")
    static let hairline = Color(hex: "#E4E6EB")
    static let border = Color(hex: "#DADDE1")

    static let ink = Color(hex: "#050505")
    static let inkSecondary = Color(hex: "#65676B")
    static let inkTertiary = Color(hex: "#8A8D91")

    static let fbBlue = Color(hex: "#1877F2")
    static let fbBlueSoft = Color(hex: "#E7F3FF")
    static let fbGreen = Color(hex: "#45BD62")
    static let fbLove = Color(hex: "#F33E58")
    static let fbWow = Color(hex: "#F7B125")
    static let fbOk = Color(hex: "#10B981")
    static let fbOrange = Color(hex: "#F59E0B")
    static let fbRed = Color(hex: "#E41E3F")
    static let fbPurple = Color(hex: "#7C3AED")
}

// MARK: - Reaction Visual Styling

extension FeedReactionType {
    var fbColor: Color {
        switch self {
        case .like: return FeedPalette.fbBlue
        case .love: return FeedPalette.fbLove
        case .wow: return FeedPalette.fbWow
        case .ok: return FeedPalette.fbOk
        }
    }

    var fbSymbol: String {
        switch self {
        case .like: return "hand.thumbsup.fill"
        case .love: return "heart.fill"
        case .wow: return "sparkles"
        case .ok: return "checkmark"
        }
    }

    var fbOutlineSymbol: String {
        switch self {
        case .like: return "hand.thumbsup"
        case .love: return "heart"
        case .wow: return "sparkles"
        case .ok: return "checkmark.circle"
        }
    }
}

// MARK: - Social Avatar

struct FeedAvatar: View {
    let avatar: String
    let name: String
    var size: CGFloat = 42
    var showOnlineDot: Bool = false
    var badgeSymbol: String? = nil
    var badgeColor: Color = FeedPalette.fbBlue

    private static let gradients: [[Color]] = [
        [Color(hex: "#1877F2"), Color(hex: "#0C57C2")],
        [Color(hex: "#0D98A5"), Color(hex: "#0A6B75")],
        [Color(hex: "#10B981"), Color(hex: "#047857")],
        [Color(hex: "#F59E0B"), Color(hex: "#D97706")],
        [Color(hex: "#EC4899"), Color(hex: "#BE185D")],
        [Color(hex: "#6366F1"), Color(hex: "#4338CA")]
    ]

    private var palette: [Color] {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return Self.gradients[abs(sum) % Self.gradients.count]
    }

    private var monogram: String {
        Self.initials(name)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarCore
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75))

            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: max(8, size * 0.22), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: max(16, size * 0.42), height: max(16, size * 0.42))
                    .background(Circle().fill(badgeColor))
                    .overlay(Circle().strokeBorder(FeedPalette.card, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            } else if showOnlineDot {
                Circle()
                    .fill(FeedPalette.fbGreen)
                    .frame(width: max(10, size * 0.27), height: max(10, size * 0.27))
                    .overlay(Circle().strokeBorder(FeedPalette.card, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
    }

    @ViewBuilder
    private var avatarCore: some View {
        if let image = AvatarImage.decode(avatar) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let url = AvatarImage.remoteURL(avatar) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    monogramFill
                }
            }
        } else {
            monogramFill
        }
    }

    private var monogramFill: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(monogram)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let joined = parts.map { String($0.prefix(1)) }.joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }

    static func resolveAvatar(
        adminId: String?,
        admins: [AdminUser],
        currentAdmin: AdminUser?
    ) -> String {
        guard let adminId, !adminId.isEmpty else { return "" }
        if let currentAdmin, currentAdmin.id == adminId, let av = currentAdmin.avatar, !av.isEmpty {
            return av
        }
        if let matched = admins.first(where: { $0.id == adminId }), let av = matched.avatar, !av.isEmpty {
            return av
        }
        return ""
    }
}

// MARK: - Facebook Circular Reaction Badge

struct FeedReactionCircle: View {
    let type: FeedReactionType
    var size: CGFloat = 19
    var ringWidth: CGFloat = 0

    var body: some View {
        Image(systemName: type.fbSymbol)
            .font(.system(size: size * 0.52, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(type.fbColor))
            .overlay {
                if ringWidth > 0 {
                    Circle().strokeBorder(FeedPalette.card, lineWidth: ringWidth)
                }
            }
    }
}

// MARK: - Overlapping Stacked Reaction Cluster

struct FeedStackedReactions: View {
    let summary: [(FeedReactionType, Int)]
    var circleSize: CGFloat = 20

    private var topTypes: [FeedReactionType] {
        summary
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.rawValue < rhs.0.rawValue
            }
            .prefix(3)
            .map(\.0)
    }

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(topTypes.enumerated()), id: \.element.id) { index, type in
                FeedReactionCircle(type: type, size: circleSize, ringWidth: 1.8)
                    .zIndex(Double(topTypes.count - index))
            }
        }
    }
}

// MARK: - Floating Facebook Reaction Dock

struct FeedFloatingReactionDock: View {
    let currentReaction: FeedReactionType?
    let onSelect: (FeedReactionType) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FeedReactionType.allCases) { type in
                let isSelected = currentReaction == type
                Button {
                    onSelect(type)
                } label: {
                    VStack(spacing: 4) {
                        FeedReactionCircle(type: type, size: isSelected ? 40 : 36)
                            .scaleEffect(isSelected ? 1.08 : 1)
                            .shadow(color: type.fbColor.opacity(0.32), radius: 5, y: 2)
                        Text(type.label)
                            .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? type.fbColor : FeedPalette.inkSecondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.label)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FeedPalette.inkSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(FeedPalette.surfaceMuted))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิดตัวเลือกความรู้สึก")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(FeedPalette.card)
                .shadow(color: Color.black.opacity(0.16), radius: 16, y: 6)
        )
        .overlay(
            Capsule()
                .strokeBorder(FeedPalette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Facebook Reactions Breakdown Sheet

struct FeedReactionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let reactions: [FeedReaction]
    let admins: [AdminUser]
    let currentAdmin: AdminUser?

    @State private var selectedFilter: FeedReactionType?

    private var summary: [(FeedReactionType, Int)] {
        var counts: [FeedReactionType: Int] = [:]
        for r in reactions { counts[r.type, default: 0] += 1 }
        return FeedReactionType.allCases
            .compactMap { type in
                guard let n = counts[type], n > 0 else { return nil }
                return (type, n)
            }
            .sorted { $0.1 > $1.1 }
    }

    private var visibleReactions: [FeedReaction] {
        guard let selectedFilter else { return reactions }
        return reactions.filter { $0.type == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterStrip
                Rectangle().fill(FeedPalette.hairline).frame(height: 1)

                if visibleReactions.isEmpty {
                    ContentUnavailableView(
                        "ยังไม่มีความรู้สึก",
                        systemImage: "hand.thumbsup",
                        description: Text("แตะถูกใจที่โพสต์เพื่อแสดงความรู้สึก")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleReactions) { reaction in
                                reactionRow(reaction)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(FeedPalette.card)
            .navigationTitle("ผู้ที่แสดงความรู้สึก")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(FeedPalette.fbBlue)
                }
            }
        }
        .preferredColorScheme(.light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterTab(title: "ทั้งหมด", count: reactions.count, type: nil)
                ForEach(summary, id: \.0.id) { pair in
                    filterTab(title: pair.0.label, count: pair.1, type: pair.0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(FeedPalette.card)
    }

    private func filterTab(title: String, count: Int, type: FeedReactionType?) -> some View {
        let isSelected = selectedFilter == type
        let tint = type?.fbColor ?? FeedPalette.fbBlue
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedFilter = type }
        } label: {
            HStack(spacing: 5) {
                if let type {
                    FeedReactionCircle(type: type, size: 18)
                }
                Text(type == nil ? title : "\(count)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(isSelected ? tint : FeedPalette.inkSecondary)
                if type == nil {
                    Text("\(count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(isSelected ? tint : FeedPalette.inkSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? tint.opacity(0.12) : FeedPalette.surfaceMuted)
            )
        }
        .buttonStyle(.plain)
    }

    private func reactionRow(_ reaction: FeedReaction) -> some View {
        let name = displayName(for: reaction.adminId)
        let avatar = FeedAvatar.resolveAvatar(
            adminId: reaction.adminId,
            admins: admins,
            currentAdmin: currentAdmin
        )
        return HStack(spacing: 12) {
            FeedAvatar(
                avatar: avatar,
                name: name,
                size: 40,
                badgeSymbol: reaction.type.fbSymbol,
                badgeColor: reaction.type.fbColor
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedPalette.ink)
                Text(reaction.type.label)
                    .font(.caption)
                    .foregroundStyle(FeedPalette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func displayName(for adminId: String) -> String {
        if let currentAdmin, currentAdmin.id == adminId {
            return "\(currentAdmin.displayName) (คุณ)"
        }
        if let matched = admins.first(where: { $0.id == adminId }) {
            return matched.displayName
        }
        return "สมาชิกทีม"
    }
}
