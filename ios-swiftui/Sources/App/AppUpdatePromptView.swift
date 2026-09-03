import SwiftUI

/// Soft-update sheet — optional TestFlight / App Store upgrade (never blocking).
struct AppUpdatePromptView: View {
    let offer: AppUpdateChecker.Offer
    var onLater: () -> Void
    var onUpdate: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onLater() }

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                card
                    .padding(.horizontal, 22)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 18)

                Spacer(minLength: 24)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 132)

                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .blur(radius: 8)
                    .offset(x: 220, y: -40)

                Circle()
                    .fill(AppTheme.cyan.opacity(0.25))
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)
                    .offset(x: -20, y: 70)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("UPDATE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                        Text(offer.sourceLabel.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.down.app.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text("มีเวอร์ชันใหม่พร้อมแล้ว")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text(offer.versionLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(20)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    versionChip(title: "ตอนนี้", value: offer.currentLine, muted: true)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                    versionChip(title: "ล่าสุด", value: offer.versionLine, muted: false)
                }

                Text(offer.message ?? "อัปเดตผ่าน TestFlight ได้เมื่อสะดวก — ไม่บังคับ")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("ปิดได้ทุกเมื่อ · เราจะเตือนอีกครั้งในภายหลัง")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)

                VStack(spacing: 10) {
                    Button(action: onUpdate) {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                            Text("อัปเดตใน TestFlight")
                                .fontWeight(.bold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.brandDark, AppTheme.brand],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("อัปเดตใน TestFlight")

                    Button(action: onLater) {
                        Text("ไว้ทีหลัง")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.surfaceSoft)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ไว้ทีหลัง")
                }
            }
            .padding(20)
            .background(AppTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.28), radius: 28, y: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func versionChip(title: String, value: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.inkMuted)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(muted ? AppTheme.inkSecondary : AppTheme.brand)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(muted ? AppTheme.surfaceSoft : AppTheme.brand.opacity(0.1))
        )
    }
}

#Preview {
    AppUpdatePromptView(
        offer: AppUpdateChecker.Offer(
            id: "1.0.1|12",
            latestVersion: "1.0.1",
            latestBuild: "12",
            currentVersion: "1.0.0",
            currentBuild: "8",
            message: "ปรับปรุงจังหวะ Real-time และหน้าวิเคราะห์ Pro",
            openURL: URL(string: "itms-beta://")!,
            sourceLabel: "TestFlight"
        ),
        onLater: {},
        onUpdate: {}
    )
}
