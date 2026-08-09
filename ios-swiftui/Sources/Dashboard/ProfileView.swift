import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppState.self) private var appState

    // Profile edit state
    @State private var displayName = ""
    @State private var avatarString = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var savingProfile = false
    @State private var profileNotice: Notice?

    // Password change state
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var savingPassword = false
    @State private var passwordNotice: Notice?

    private struct Notice: Equatable {
        let ok: Bool
        let text: String
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spaceLG) {
                profileCard
                editCard
                passwordCard
                realtimeDiagnosticsCard
                aboutCard
            }
            .padding(AppTheme.spaceLG)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("โปรไฟล์")
        .navigationBarTitleDisplayMode(.large)
        .task { syncFromAdmin() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadAvatar(item) }
        }
    }

    // MARK: - Header card

    private var profileCard: some View {
        SectionCard {
            HStack(spacing: 16) {
                AvatarCircle(avatar: avatarString, initials: initials, size: 72)

                VStack(alignment: .leading, spacing: 6) {
                    Text(auth.currentAdmin?.displayName ?? "—")
                        .font(.title3.bold())
                    if let username = auth.currentAdmin?.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        PillBadge(text: accountLevelLabel, color: AppTheme.brand)
                        if let last = auth.currentAdmin?.lastLogin, !last.isEmpty {
                            Text("เข้าล่าสุด \(String(last.prefix(16)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Edit profile (display name, picture, account level)

    private var editCard: some View {
        SectionCard("แก้ไขโปรไฟล์", systemImage: "person.crop.circle.badge.plus") {
            VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                // Picture
                HStack(spacing: 16) {
                    AvatarCircle(avatar: avatarString, initials: initials, size: 60)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label("แก้ไขรูป", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                        }
                        if !avatarString.isEmpty {
                            Button(role: .destructive) {
                                avatarString = ""
                                photoItem = nil
                            } label: {
                                Label("ลบรูป", systemImage: "trash")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                Divider()

                // Display name
                VStack(alignment: .leading, spacing: 6) {
                    Text("ชื่อที่แสดง")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("ชื่อที่แสดง", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Divider()

                // Account level (read-only)
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.brand)
                        .frame(width: 22)
                    Text("ระดับบัญชี")
                        .foregroundStyle(.secondary)
                    Spacer()
                    PillBadge(text: accountLevelLabel, color: AppTheme.brand)
                }
                .font(.subheadline)

                if let profileNotice {
                    noticeBanner(profileNotice)
                }

                Button {
                    Task { await saveProfile() }
                } label: {
                    HStack {
                        if savingProfile { ProgressView().tint(.white) }
                        Text(savingProfile ? "กำลังบันทึก…" : "บันทึกโปรไฟล์")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
                .disabled(savingProfile || !profileHasChanges)
            }
        }
    }

    // MARK: - Change password

    private var passwordCard: some View {
        SectionCard("เปลี่ยนรหัสผ่าน", systemImage: "lock.fill") {
            VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                secureField("รหัสผ่านปัจจุบัน", text: $currentPassword, content: .password)
                secureField("รหัสผ่านใหม่ (อย่างน้อย 8 ตัว)", text: $newPassword, content: .newPassword)
                secureField("ยืนยันรหัสผ่านใหม่", text: $confirmPassword, content: .newPassword)

                if let passwordNotice {
                    noticeBanner(passwordNotice)
                }

                Button {
                    Task { await savePassword() }
                } label: {
                    HStack {
                        if savingPassword { ProgressView() }
                        Text(savingPassword ? "กำลังบันทึก…" : "เปลี่ยนรหัสผ่าน")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.brand)
                .disabled(savingPassword || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
            }
        }
    }

    // MARK: - About / logout

    private var realtimeDiagnosticsCard: some View {
        let supervisor = RealtimeBuildSupervisor.shared
        let watchdog = MainThreadWatchdog.shared
        return SectionCard("Real-time diagnostics", systemImage: "gauge.with.dots.needle.67percent") {
            row(icon: "tray.full", title: "ธุรกรรมในเครื่อง", value: "\(appState.lastFetchTransactionCount)")
            Divider()
            row(icon: "arrow.triangle.2.circlepath", title: "transactionsRevision", value: "\(appState.transactionsRevision)")
            Divider()
            row(
                icon: "timer",
                title: "lastBuildMs",
                value: supervisor.lastBuildMs > 0 ? "\(Int(supervisor.lastBuildMs.rounded())) ms" : "—"
            )
            Divider()
            row(
                icon: "bolt.slash",
                title: "โหมดประหยัด",
                value: supervisor.isEconomyMode ? "เปิด" : "ปิด"
            )
            Divider()
            row(icon: "exclamationmark.triangle", title: "hangCount", value: "\(watchdog.hangCount)")
            if watchdog.lastHangMs > 0 {
                Divider()
                row(icon: "clock.badge.exclamationmark", title: "lastHangMs", value: "\(Int(watchdog.lastHangMs.rounded())) ms")
            }
        }
    }

    private var aboutCard: some View {
        SectionCard("เกี่ยวกับ", systemImage: "info.circle.fill") {
            row(icon: "iphone", title: "เวอร์ชัน", value: appVersion)
            Divider()
            Button(role: .destructive) {
                appState.clearLocalData()
                auth.logout()
            } label: {
                Label("ออกจากระบบ", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func syncFromAdmin() {
        guard let admin = auth.currentAdmin else { return }
        displayName = admin.displayName
        avatarString = admin.avatar ?? ""
    }

    private func saveProfile() async {
        savingProfile = true
        profileNotice = nil
        do {
            try await auth.updateProfile(displayName: displayName, avatar: avatarString)
            profileNotice = Notice(ok: true, text: "บันทึกโปรไฟล์แล้ว")
        } catch {
            profileNotice = Notice(ok: false, text: error.localizedDescription)
        }
        savingProfile = false
    }

    private func savePassword() async {
        passwordNotice = nil
        guard newPassword == confirmPassword else {
            passwordNotice = Notice(ok: false, text: "รหัสผ่านใหม่ทั้งสองช่องไม่ตรงกัน")
            return
        }
        savingPassword = true
        do {
            try await auth.changePassword(current: currentPassword, newPassword: newPassword)
            passwordNotice = Notice(ok: true, text: "เปลี่ยนรหัสผ่านเรียบร้อย")
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            passwordNotice = Notice(ok: false, text: error.localizedDescription)
        }
        savingPassword = false
    }

    private func loadAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let encoded = AvatarImage.encode(image) else {
            profileNotice = Notice(ok: false, text: "โหลดรูปไม่สำเร็จ ลองรูปอื่น")
            return
        }
        avatarString = encoded
    }

    // MARK: - Small helpers

    private var profileHasChanges: Bool {
        guard let admin = auth.currentAdmin else { return false }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != admin.displayName || avatarString != (admin.avatar ?? "")
    }

    private var accountLevelLabel: String {
        auth.currentAdmin?.role.rawValue ?? "Admin"
    }

    private func secureField(_ title: String, text: Binding<String>, content: UITextContentType) -> some View {
        SecureField(title, text: text)
            .textContentType(content)
            .padding(12)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func noticeBanner(_ notice: Notice) -> some View {
        Text(notice.text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(notice.ok ? AppTheme.income : AppTheme.expense)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                (notice.ok ? AppTheme.income : AppTheme.expense).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var initials: String {
        let name = auth.currentAdmin?.displayName ?? auth.currentAdmin?.username ?? "?"
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        if parts.isEmpty { return "?" }
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

// MARK: - Avatar rendering + encoding

/// Circular avatar that shows a stored image (data: URL or http URL) or falls back to initials.
struct AvatarCircle: View {
    let avatar: String
    let initials: String
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.brand, AppTheme.brandMid],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let image = AvatarImage.decode(avatar) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = AvatarImage.remoteURL(avatar) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

enum AvatarImage {
    /// Encodes a UIImage into a compact `data:image/jpeg;base64,...` string (downscaled avatar).
    static func encode(_ image: UIImage, maxDimension: CGFloat = 256) -> String? {
        let resized = resize(image, maxDimension: maxDimension)
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    static func decode(_ avatar: String) -> UIImage? {
        guard avatar.hasPrefix("data:"),
              let commaIndex = avatar.firstIndex(of: ",") else { return nil }
        let base64 = String(avatar[avatar.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    static func remoteURL(_ avatar: String) -> URL? {
        guard avatar.hasPrefix("http") else { return nil }
        return URL(string: avatar)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
