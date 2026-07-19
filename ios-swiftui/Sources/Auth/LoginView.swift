import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var profilesStore = SavedProfilesStore.shared

    @State private var username = ""
    @State private var password = ""
    @State private var rememberProfile = true
    @State private var showForm = false
    @State private var isSubmitting = false
    @State private var unlockingProfileId: String?
    @State private var errorText: String?
    @State private var showPassword = false
    @State private var appeared = false
    @State private var shakeTrigger = 0
    @State private var profilePendingRemove: SavedLoginProfile?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username, password
    }

    private var hasSavedProfiles: Bool {
        !profilesStore.profiles.isEmpty
    }

    private var showingPicker: Bool {
        hasSavedProfiles && !showForm
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 56)

                    brandHeader
                        .padding(.bottom, 40)

                    Group {
                        if showingPicker {
                            profilePicker
                        } else {
                            formCard
                        }
                    }
                    .padding(.horizontal, 28)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

                    Spacer(minLength: 48)
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            showForm = !hasSavedProfiles
            playEntrance()
        }
        .onChange(of: profilesStore.profiles.count) { count in
            if count == 0 {
                showForm = true
            }
        }
        .confirmationDialog(
            "ลบโปรไฟล์นี้?",
            isPresented: Binding(
                get: { profilePendingRemove != nil },
                set: { if !$0 { profilePendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = profilePendingRemove {
                Button("ลบ \(profile.displayName)", role: .destructive) {
                    withAnimation {
                        profilesStore.remove(id: profile.id)
                    }
                    profilePendingRemove = nil
                }
            }
            Button("ยกเลิก", role: .cancel) {
                profilePendingRemove = nil
            }
        } message: {
            Text("จะต้องเข้าสู่ระบบด้วยชื่อผู้ใช้และรหัสผ่านอีกครั้ง")
        }
    }

    // MARK: - Entrance

    private func playEntrance() {
        if reduceMotion {
            appeared = true
            return
        }
        // Slight delay so splash exit and login entrance don't compete.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.spring(response: 0.62, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            // Single soft brand glow — premium, not busy
            Circle()
                .fill(AppTheme.brand.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: 100, y: -220)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var brandHeader: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .animation(entranceAnimation(delay: 0.05), value: appeared)

            VStack(spacing: 6) {
                Text("Goldenmole")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Dashboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(3.2)
                    .textCase(.uppercase)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(entranceAnimation(delay: 0.16), value: appeared)
        }
        .animation(entranceAnimation(delay: 0.05), value: appeared)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goldenmole Dashboard")
    }

    private func entranceAnimation(delay: Double) -> Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.18).delay(delay)
        }
        return .spring(response: 0.62, dampingFraction: 0.8).delay(delay)
    }

    // MARK: - Card chrome

    private func premiumCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 32)
            .animation(entranceAnimation(delay: 0.28), value: appeared)
    }

    // MARK: - Profile picker

    private var profilePicker: some View {
        premiumCard {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("เลือกโปรไฟล์")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("แตะเพื่อเข้าด้วย \(BiometricAuth.biometryLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(profilesStore.profiles) { profile in
                        profileCard(profile)
                    }
                }

                if let errorText {
                    errorBanner(errorText)
                }

                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85)) {
                        username = ""
                        password = ""
                        errorText = nil
                        showForm = true
                    }
                } label: {
                    Text("ใช้บัญชีอื่น")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || unlockingProfileId != nil)
            }
        }
    }

    private func profileCard(_ profile: SavedLoginProfile) -> some View {
        let isUnlocking = unlockingProfileId == profile.id
        let busy = isSubmitting || unlockingProfileId != nil

        return VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button {
                    Task { await unlockProfile(profile) }
                } label: {
                    avatarCircle(for: profile)
                        .overlay {
                            if isUnlocking {
                                Circle()
                                    .fill(Color.black.opacity(0.28))
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("เข้าสู่ระบบด้วย \(profile.displayName)")

                Button {
                    profilePendingRemove = profile
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .disabled(busy)
                .accessibilityLabel("ลบโปรไฟล์ \(profile.displayName)")
            }

            Button {
                Task { await unlockProfile(profile) }
            } label: {
                VStack(spacing: 2) {
                    Text(profile.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(profile.username)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(.vertical, 4)
    }

    private func avatarCircle(for profile: SavedLoginProfile) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.brand, AppTheme.brandMid],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 68, height: 68)
                .shadow(color: AppTheme.brand.opacity(0.22), radius: 8, y: 4)

            if let avatar = profile.avatar, let url = URL(string: avatar), !avatar.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Text(profile.initials)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(Circle())
            } else {
                Text(profile.initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Form

    private var formCard: some View {
        premiumCard {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("เข้าสู่ระบบ")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("ใช้บัญชีแอดมินเดียวกับเว็บ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    fieldRow(systemImage: "person", field: .username) {
                        TextField("ชื่อผู้ใช้", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .username)
                            .onSubmit { focusedField = .password }
                    }

                    fieldRow(systemImage: "lock", field: .password) {
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
                            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.75)) {
                                showPassword.toggle()
                            }
                        } label: {
                            Group {
                                if #available(iOS 17.0, *) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .contentTransition(.symbolEffect(.replace))
                                } else {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "ซ่อนรหัสผ่าน" : "แสดงรหัสผ่าน")
                    }
                }

                Toggle(isOn: $rememberProfile) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("จำโปรไฟล์นี้")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("เข้าครั้งถัดไปได้เร็วขึ้นด้วย \(BiometricAuth.biometryLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppTheme.brand)

                if let errorText {
                    errorBanner(errorText)
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
                                .font(.headline.weight(.semibold))
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
                .buttonStyle(LoginPrimaryButtonStyle(enabled: canSubmit))
                .disabled(!canSubmit)
                .accessibilityLabel("เข้าสู่ระบบ")

                if hasSavedProfiles {
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85)) {
                            errorText = nil
                            showForm = false
                        }
                    } label: {
                        Text("กลับไปเลือกโปรไฟล์")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.brand)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(AppTheme.expense)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.expense.opacity(0.12))
        )
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        )
        .accessibilityLabel("ข้อผิดพลาด: \(message)")
    }

    private var canSubmit: Bool {
        !isSubmitting
            && unlockingProfileId == nil
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fieldRow<Content: View>(
        systemImage: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focusedField == field
        return HStack(spacing: 12) {
            fieldIcon(systemImage: systemImage, isFocused: isFocused)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFocused ? AppTheme.brand.opacity(0.65) : Color.primary.opacity(0.06),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(color: isFocused ? AppTheme.brand.opacity(0.14) : .clear, radius: isFocused ? 8 : 0, y: 2)
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85),
            value: focusedField
        )
    }

    @ViewBuilder
    private func fieldIcon(systemImage: String, isFocused: Bool) -> some View {
        let icon = Image(systemName: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isFocused ? AppTheme.brand : .secondary)
            .frame(width: 20)
            .scaleEffect(isFocused ? 1.06 : 1.0)

        if #available(iOS 17.0, *), !reduceMotion {
            icon.symbolEffect(.bounce, value: isFocused)
        } else {
            icon
        }
    }

    // MARK: - Actions

    private func unlockProfile(_ profile: SavedLoginProfile) async {
        unlockingProfileId = profile.id
        withAnimation {
            errorText = nil
        }

        do {
            if BiometricAuth.canEvaluate {
                try await BiometricAuth.authenticate(
                    reason: "เข้าสู่ระบบด้วยโปรไฟล์ \(profile.displayName)"
                )
            }
            try await auth.loginWithSavedProfile(id: profile.id)
            await appState.loadInitial()
        } catch let bio as BiometricAuthError {
            switch bio {
            case .cancelled, .unavailable:
                username = profile.username
                password = ""
                rememberProfile = true
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85)) {
                    showForm = true
                }
            case .failed:
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.75)) {
                    errorText = bio.errorDescription
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.75)) {
                errorText = message
            }
            if !reduceMotion {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.35)) {
                    shakeTrigger += 1
                }
            }
            if let authError = error as? AuthError, case .savedProfileMissing = authError {
                username = profile.username
                password = ""
                rememberProfile = true
                showForm = true
            }
        }

        unlockingProfileId = nil
    }

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85)) {
            errorText = nil
        }
        do {
            try await auth.login(
                username: username,
                password: password,
                rememberProfile: rememberProfile
            )
            await appState.loadInitial()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.75)) {
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
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: enabled
                                ? [AppTheme.brand, AppTheme.brandMid]
                                : [AppTheme.brand.opacity(0.45), AppTheme.brandMid.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(
                color: enabled ? AppTheme.brand.opacity(configuration.isPressed ? 0.18 : 0.28) : .clear,
                radius: configuration.isPressed ? 6 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
            .opacity(configuration.isPressed && enabled ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
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
