import Foundation

enum AuthError: LocalizedError {
    case invalidCredentials
    case notConfigured
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง"
        case .notConfigured:
            return "ยังไม่ได้ตั้งค่า Supabase"
        case .network(let detail):
            return "เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — \(detail)"
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    private let dataService: SupabaseService
    private let sessionKey = "goldenmole.dashboard.session.adminId"

    @Published private(set) var currentAdmin: AdminUser?

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

    func login(username: String, password: String) async throws {
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
        await dataService.updateAdminLastLogin(id: matched.id)
    }

    func logout() {
        currentAdmin = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    private func normalizeUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
