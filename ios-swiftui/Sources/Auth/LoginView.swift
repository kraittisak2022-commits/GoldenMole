import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    private enum Field {
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
    }

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
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 280, height: 280)
                    .blur(radius: 40)
                    .offset(x: 140, y: -220)
                Circle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 320, height: 320)
                    .blur(radius: 50)
                    .offset(x: -160, y: 340)
            }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            Text("Goldenmole")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Dashboard")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(2)
                .textCase(.uppercase)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goldenmole Dashboard")
    }

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
                fieldRow(systemImage: "person.fill") {
                    TextField("ชื่อผู้ใช้", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                }

                fieldRow(systemImage: "lock.fill") {
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
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
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
                .accessibilityLabel("ข้อผิดพลาด: \(errorText)")
            }

            Button {
                Task { await submit() }
            } label: {
                ZStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("เข้าสู่ระบบ")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canSubmit ? brand : brand.opacity(0.45))
            )
            .disabled(!canSubmit)
            .accessibilityLabel("เข้าสู่ระบบ")
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        )
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fieldRow<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(brand)
                .frame(width: 20)
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
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        errorText = nil
        do {
            try await auth.login(username: username, password: password)
            // Navigate via AuthGateView observing currentAdmin.
            // Dashboard load failures must not keep the user on login.
            await appState.loadInitial()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSubmitting = false
    }
}
