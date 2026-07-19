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

    func logout() {
        currentAdmin = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
        // Keep saved profiles (Facebook-style).
    }

    private func normalizeUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
