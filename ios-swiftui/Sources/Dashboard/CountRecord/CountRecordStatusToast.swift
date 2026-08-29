import SwiftUI

/// Floating pro toast for count-record status updates.
struct CountRecordStatusToast: View {
    let message: String
    let isError: Bool
    let onDismiss: () -> Void

    @State private var appeared = false

    private var accent: Color {
        isError ? AppTheme.expense : Color(hex: "#AD1457")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "sparkles")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(Color.white.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(isError ? "แจ้งเตือน" : "อัปเดตแล้ว")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.78))
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isError
                            ? [Color(hex: "#BE123C"), Color(hex: "#E11D48")]
                            : [Color(hex: "#9D174D"), Color(hex: "#DB2777"), Color(hex: "#7C3AED")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: accent.opacity(0.45), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                appeared = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                onDismiss()
            }
        }
        .accessibilityAddTraits(.isStaticText)
    }
}
