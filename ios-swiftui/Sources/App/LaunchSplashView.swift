import SwiftUI

/// Premium branded splash shown while the app bootstraps.
struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var pulse = false
    @State private var loaderPhase = 0
    @State private var loaderTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                logoBlock

                brandCopy

                Spacer(minLength: 0)

                premiumLoader
                    .padding(.bottom, 56)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { playEntrance() }
        .onDisappear {
            loaderTask?.cancel()
            loaderTask = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goldenmole Dashboard กำลังเริ่มต้น")
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            Circle()
                .fill(AppTheme.brand.opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(y: -40)
                .scaleEffect(pulse && !reduceMotion ? 1.08 : 1)
                .ignoresSafeArea()
        }
    }

    // MARK: - Logo

    private var logoBlock: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(AppTheme.brand.opacity(pulse ? 0.18 : 0.08), lineWidth: 1.5)
                    .frame(width: 128, height: 128)
                    .scaleEffect(pulse ? 1.18 : 1)
                    .opacity(pulse ? 0 : 0.9)

                Circle()
                    .stroke(AppTheme.brand.opacity(0.12), lineWidth: 1)
                    .frame(width: 112, height: 112)
            }

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: AppTheme.brand.opacity(0.22), radius: 18, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .scaleEffect(appeared ? 1 : 0.82)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Brand

    private var brandCopy: some View {
        VStack(spacing: 8) {
            Text("Goldenmole")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Dashboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(3.6)
                .textCase(.uppercase)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(entrance(delay: 0.12), value: appeared)
    }

    // MARK: - Loader

    private var premiumLoader: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppTheme.brand)
                    .frame(width: 7, height: 7)
                    .opacity(dotOpacity(for: index))
                    .scaleEffect(dotScale(for: index))
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(entrance(delay: 0.28), value: appeared)
        .accessibilityHidden(true)
    }

    private func dotOpacity(for index: Int) -> Double {
        if reduceMotion { return 0.45 }
        return loaderPhase == index ? 1 : 0.28
    }

    private func dotScale(for index: Int) -> CGFloat {
        if reduceMotion { return 1 }
        return loaderPhase == index ? 1.25 : 0.85
    }

    // MARK: - Motion

    private func playEntrance() {
        if reduceMotion {
            appeared = true
            return
        }

        withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) {
            appeared = true
        }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse = true
        }

        loaderTask?.cancel()
        loaderTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    loaderPhase = (loaderPhase + 1) % 3
                }
            }
        }
    }

    private func entrance(delay: Double) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.18).delay(delay)
        }
        return .spring(response: 0.6, dampingFraction: 0.82).delay(delay)
    }
}
