import Foundation
import Observation

enum AuthError: LocalizedError {
    case invalidCredentials
    case notConfigured
    case network(String)
    case savedProfileMissing

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง"
        case .notConfigured:
            return "ยังไม่ได้ตั้งค่า Supabase"
        case .network(let detail):
            return "เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — \(detail)"
        case .savedProfileMissing:
            return "ไม่พบรหัสผ่านของโปรไฟล์นี้ — กรุณาเข้าสู่ระบบใหม่"
        }
    }
}

enum ProfileError: LocalizedError {
    case notLoggedIn
    case emptyName
    case currentPasswordWrong
    case weakPassword
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "ไม่พบผู้ใช้ที่เข้าสู่ระบบ"
        case .emptyName: return "กรุณาระบุชื่อที่แสดง"
        case .currentPasswordWrong: return "รหัสผ่านปัจจุบันไม่ถูกต้อง"
        case .weakPassword: return "รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร"
        case .network(let detail): return "บันทึกไม่สำเร็จ — \(detail)"
        }
    }
}

@MainActor
@Observable
final class AuthService {
    @ObservationIgnored private let dataService: SupabaseService
    @ObservationIgnored private let sessionKey = "goldenmole.dashboard.session.adminId"
    @ObservationIgnored private let profilesStore = SavedProfilesStore.shared

    private(set) var currentAdmin: AdminUser?

    init(dataService: SupabaseService) {
        self.dataService = dataService
    }

    func restoreSession() async {
        guard let adminId = UserDefaults.standard.string(forKey: sessionKey) else { return }
        do {
            let admins = try await dataService.fetchAdmins()
            currentAdmin = admins.first { $0.id == adminId }
            if currentAdmin == nil {
                UserDefaults.standard.removeObject(forKey: sessionKey)
            }
        } catch {
            currentAdmin = nil
        }
    }

    func login(username: String, password: String, rememberProfile: Bool = false) async throws {
        let normalized = normalizeUsername(username)
        let plainPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !plainPassword.isEmpty else {
            throw AuthError.invalidCredentials
        }

        let admins: [AdminUser]
        do {
            admins = try await dataService.fetchAdmins()
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        guard let matched = admins.first(where: { normalizeUsername($0.username) == normalized }) else {
            throw AuthError.invalidCredentials
        }
        guard PasswordAuth.verify(stored: matched.password, inputPlain: plainPassword) else {
            throw AuthError.invalidCredentials
        }

        // Persist session first so UI can navigate even if last_login update fails.
        currentAdmin = matched
        UserDefaults.standard.set(matched.id, forKey: sessionKey)
        // Attribute later crash/error reports to this user (persists across launches).
        ErrorReportCenter.setReporter(username: matched.username, name: matched.displayName)

        if rememberProfile {
            profilesStore.save(from: matched, password: plainPassword)
        }

        await dataService.updateAdminLastLogin(id: matched.id)
    }

    func loginWithSavedProfile(id: String) async throws {
        guard let profile = profilesStore.profiles.first(where: { $0.id == id }),
              let password = profilesStore.password(for: id)
        else {
            throw AuthError.savedProfileMissing
        }

        do {
            try await login(username: profile.username, password: password, rememberProfile: true)
            profilesStore.touch(id: id)
        } catch AuthError.invalidCredentials {
            profilesStore.remove(id: id)
            throw AuthError.savedProfileMissing
        }
    }

    /// Updates display name + avatar for the signed-in admin (mirrors web My Account).
    func updateProfile(displayName: String, avatar: String?) async throws {
        guard let admin = currentAdmin else { throw ProfileError.notLoggedIn }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileError.emptyName }
        let av = (avatar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await dataService.updateAdminProfile(id: admin.id, fields: ["display_name": name, "avatar": av])
        } catch {
            throw ProfileError.network(error.localizedDescription)
        }

        currentAdmin = admin.copy(displayName: name, avatar: .some(av))
        profilesStore.updateProfileInfo(id: admin.id, displayName: name, avatar: av)
        ErrorReportCenter.setReporter(username: admin.username, name: name)
    }

    /// Verifies the current password, then stores a new SHA-256 hash (mirrors web).
    func changePassword(current: String, newPassword: String) async throws {
        guard let admin = currentAdmin else { throw ProfileError.notLoggedIn }
        let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PasswordAuth.verify(stored: admin.password, inputPlain: cur) else {
            throw ProfileError.currentPasswordWrong
        }
        guard new.count >= 8 else { throw ProfileError.weakPassword }

        let hashed = PasswordAuth.hashForStorage(new)
        do {
            try await dataService.updateAdminProfile(id: admin.id, fields: ["password": hashed])
        } catch {
            throw ProfileError.network(error.localizedDescription)
        }

        currentAdmin = admin.copy(password: hashed)
        profilesStore.updatePassword(id: admin.id, password: new)
    }

    func logout() {
        currentAdmin = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
        // Keep saved profiles (Facebook-style). Wipe read-model disk cache for the next session.
        LocalDataCache.invalidate()
    }

    private func normalizeUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
