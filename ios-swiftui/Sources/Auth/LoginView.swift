import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var showPassword = false
    @State private var appeared = false
    @State private var ambientPhase = false
    @State private var shakeTrigger = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username, password
    }

    private let brand = Color(hex: "#0D98A5")

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 48)

                    brandHeader
                        .padding(.bottom, 36)

                    formCard
                        .padding(.horizontal, 24)
                        .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onTapGesture {
            focusedField = nil
        }
        .onAppear { playEntrance() }
    }

    // MARK: - Entrance

    private func playEntrance() {
        if reduceMotion {
            appeared = true
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            appeared = true
        }
        withAnimation(
            .easeInOut(duration: 9)
            .repeatForever(autoreverses: true)
        ) {
            ambientPhase = true
        }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                Color(hex: "#063A40"),
                Color(hex: "#0A6B75"),
                brand.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 280, height: 280)
                    .blur(radius: 40)
                    .scaleEffect(ambientScale(base: 1.0, delta: 0.12))
                    .offset(
                        x: ambientOffset(from: 120, to: 160),
                        y: ambientOffset(from: -240, to: -190)
                    )

                Circle()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 320, height: 320)
                    .blur(radius: 50)
                    .scaleEffect(ambientScale(base: 1.05, delta: -0.08))
                    .offset(
                        x: ambientOffset(from: -170, to: -130),
                        y: ambientOffset(from: 320, to: 360)
                    )

                Circle()
                    .fill(brand.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 36)
                    .scaleEffect(ambientScale(base: 0.95, delta: 0.15))
                    .offset(
                        x: ambientOffset(from: -40, to: 30),
                        y: ambientOffset(from: 80, to: 40)
                    )
            }
        }
    }

    private func ambientScale(base: CGFloat, delta: CGFloat) -> CGFloat {
        guard !reduceMotion else { return base }
        return ambientPhase ? base + delta : base
    }

    private func ambientOffset(from: CGFloat, to: CGFloat) -> CGFloat {
        guard !reduceMotion else { return from }
        return ambientPhase ? to : from
    }

    // MARK: - Header

    private var brandHeader: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text("Goldenmole")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Dashboard")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .tracking(2)
                    .textCase(.uppercase)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(entranceAnimation(delay: 0.15), value: appeared)
        }
        .animation(entranceAnimation(delay: 0), value: appeared)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goldenmole Dashboard")
    }

    private func entranceAnimation(delay: Double) -> Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.2).delay(delay)
        }
        return .spring(response: 0.6, dampingFraction: 0.78).delay(delay)
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("เข้าสู่ระบบ")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text("ใช้บัญชีแอดมินเดียวกับเว็บ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                fieldRow(systemImage: "person.fill", field: .username) {
                    TextField("ชื่อผู้ใช้", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                }

                fieldRow(systemImage: "lock.fill", field: .password) {
                    Group {
                        if showPassword {
                            TextField("รหัสผ่าน", text: $password)
                        } else {
                            SecureField("รหัสผ่าน", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { Task { await submit() } }

                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.7)) {
                            showPassword.toggle()
                        }
                    } label: {
                        Group {
                            if #available(iOS 17.0, *) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .contentTransition(.symbolEffect(.replace))
                            } else {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "ซ่อนรหัสผ่าน" : "แสดงรหัสผ่าน")
                }
            }

            if let errorText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(errorText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(Color(hex: "#DC2626"))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "#FEE2E2"))
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .accessibilityLabel("ข้อผิดพลาด: \(errorText)")
            }

            Button {
                Task { await submit() }
            } label: {
                ZStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                            .transition(.opacity)
                    } else {
                        Text("เข้าสู่ระบบ")
                            .font(.headline)
                            .transition(.opacity)
                    }
                }
                .animation(
                    reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85),
                    value: isSubmitting
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(LoginPrimaryButtonStyle(brand: brand, enabled: canSubmit))
            .disabled(!canSubmit)
            .accessibilityLabel("เข้าสู่ระบบ")
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 36)
        .animation(entranceAnimation(delay: 0.3), value: appeared)
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fieldRow<Content: View>(
        systemImage: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focusedField == field
        return HStack(spacing: 10) {
            fieldIcon(systemImage: systemImage, isFocused: isFocused)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? brand : Color.black.opacity(0.06), lineWidth: isFocused ? 1.5 : 1)
        )
        .shadow(color: isFocused ? brand.opacity(0.22) : .clear, radius: isFocused ? 8 : 0, y: 2)
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85),
            value: focusedField
        )
    }

    @ViewBuilder
    private func fieldIcon(systemImage: String, isFocused: Bool) -> some View {
        let icon = Image(systemName: systemImage)
            .foregroundStyle(brand)
            .frame(width: 20)
            .scaleEffect(isFocused ? 1.08 : 1.0)

        if #available(iOS 17.0, *), !reduceMotion {
            icon.symbolEffect(.bounce, value: isFocused)
        } else {
            icon
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85)) {
            errorText = nil
        }
        do {
            try await auth.login(username: username, password: password)
            await appState.loadInitial()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7)) {
                errorText = message
            }
            if !reduceMotion {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.35)) {
                    shakeTrigger += 1
                }
            }
        }
        isSubmitting = false
    }
}

// MARK: - Button style

private struct LoginPrimaryButtonStyle: ButtonStyle {
    let brand: Color
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? brand : brand.opacity(0.45))
            )
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .opacity(configuration.isPressed && enabled ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shake

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 4) * 8
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
