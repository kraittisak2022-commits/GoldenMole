import SwiftUI

// MARK: - Breathing pulse (FAB, live badges)

struct TasksBreathingPulse: ViewModifier {
    @State private var scale: CGFloat = 1
    var enabled: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled ? scale : 1)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    scale = 1.06
                }
            }
    }
}

extension View {
    func tasksBreathingPulse(_ enabled: Bool = true) -> some View {
        modifier(TasksBreathingPulse(enabled: enabled))
    }
}

// MARK: - Staggered list appear

struct TasksStaggeredAppear: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .scaleEffect(visible ? 1 : 0.97)
            .onAppear {
                let delay = baseDelay + Double(min(index, 12)) * 0.045
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82).delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func tasksStaggeredAppear(index: Int, baseDelay: Double = 0) -> some View {
        modifier(TasksStaggeredAppear(index: index, baseDelay: baseDelay))
    }
}

// MARK: - Shimmer sweep (composer / hero accents)

struct TasksShimmerSweep: ViewModifier {
    @State private var phase: CGFloat = -1.2
    var active: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.35),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: geo.size.width * phase)
                        .blendMode(.softLight)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                            phase = 1.35
                        }
                    }
                }
            }
    }
}

extension View {
    func tasksShimmer(_ active: Bool = true) -> some View {
        modifier(TasksShimmerSweep(active: active))
    }
}

// MARK: - Glass KPI tile

struct TasksGlassKPITile: View {
    let title: String
    let value: Int
    let tint: Color
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint.opacity(0.85))
            }
            Text("\(value)")
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: tint.opacity(0.12), radius: 8, y: 3)
    }
}

// MARK: - Floating orbs (hero background)

struct TasksHeroOrbs: View {
    @State private var drift = false
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 200, height: 200)
                .blur(radius: 28)
                .offset(x: drift ? 220 : 200, y: drift ? -60 : -70)
            Circle()
                .fill(AppTheme.cyan.opacity(0.28))
                .frame(width: 120, height: 120)
                .blur(radius: 22)
                .offset(x: drift ? -30 : -50, y: drift ? 140 : 120)
            Circle()
                .fill(AppTheme.brand.opacity(0.22))
                .frame(width: 80, height: 80)
                .blur(radius: 18)
                .offset(x: drift ? 120 : 100, y: drift ? 90 : 70)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - Completion burst

struct TasksCelebrateBurst: View {
    let token: Int
    var reduceMotion: Bool

    private let colors: [Color] = [
        AppTheme.income, AppTheme.brand, AppTheme.cyan,
        AppTheme.warning, Color(hex: "#A78BFA"),
    ]

    var body: some View {
        ZStack {
            if token > 0, !reduceMotion {
                ForEach(0..<18, id: \.self) { i in
                    CelebrateParticle(
                        index: i,
                        color: colors[i % colors.count],
                        token: token
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CelebrateParticle: View {
    let index: Int
    let color: Color
    let token: Int
    @State private var progress: CGFloat = 0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6 + CGFloat(index % 4), height: 6 + CGFloat(index % 4))
            .offset(
                x: cos(Double(index) * 0.7) * 80 * progress,
                y: sin(Double(index) * 0.9) * 80 * progress - 40 * progress
            )
            .opacity(Double(1 - progress))
            .scaleEffect(1 - progress * 0.3)
            .onChange(of: token) { _, _ in
                progress = 0
                withAnimation(.easeOut(duration: 0.75)) {
                    progress = 1
                }
            }
    }
}

// MARK: - Bell wiggle (inbox)

struct TasksBellWiggle: ViewModifier {
    var active: Bool
    var reduceMotion: Bool
    @State private var wiggle = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(wiggle ? 8 : -8))
            .onAppear { triggerIfNeeded() }
            .onChange(of: active) { _, _ in triggerIfNeeded() }
    }

    private func triggerIfNeeded() {
        guard active, !reduceMotion else { return }
        wiggle = false
        withAnimation(.easeInOut(duration: 0.12).repeatCount(5, autoreverses: true)) {
            wiggle = true
        }
    }
}

extension View {
    func tasksBellWiggle(active: Bool, reduceMotion: Bool) -> some View {
        modifier(TasksBellWiggle(active: active, reduceMotion: reduceMotion))
    }
}

// MARK: - Pro section header

struct TasksProSectionHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color = AppTheme.brand
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: systemImage)
                    .font(.body.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(tint))
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Animated progress ring

struct TasksAnimatedProgressRing: View {
    let progress: Double
    let centerTitle: String
    let centerSubtitle: String
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, progress)))
                .stroke(
                    AngularGradient(
                        colors: [.white.opacity(0.55), .white, AppTheme.cyan, AppTheme.brand],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: AppTheme.cyan.opacity(reduceMotion ? 0 : 0.45), radius: 6)
            VStack(spacing: 1) {
                Text(centerTitle)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(centerSubtitle)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .minimumScaleFactor(0.6)
        }
        .frame(width: 76, height: 76)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: progress)
    }
}

// MARK: - Live pulse dot

struct TasksLivePulse: View {
    var color: Color = Color(hex: "#4ADE80")
    var reduceMotion: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: pulse ? 14 : 6, height: pulse ? 14 : 6)
                    .opacity(pulse ? 0 : 0.8)
            }
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: reduceMotion ? .clear : color.opacity(0.8), radius: 4)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
