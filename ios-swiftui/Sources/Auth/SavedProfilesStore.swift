import Foundation

struct SavedLoginProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatar: String?
    var lastUsedAt: Date

    var initials: String {
        let parts = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        if parts.isEmpty {
            return String(username.prefix(1)).uppercased()
        }
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

@MainActor
final class SavedProfilesStore: ObservableObject {
    static let shared = SavedProfilesStore()

    private let defaultsKey = "goldenmole.dashboard.savedProfiles"
    private let maxProfiles = 5

    @Published private(set) var profiles: [SavedLoginProfile] = []

    private init() {
        profiles = load()
    }

    func save(from admin: AdminUser, password: String) {
        KeychainStore.setPassword(password, account: admin.id)

        var next = profiles.filter { $0.id != admin.id }
        next.insert(
            SavedLoginProfile(
                id: admin.id,
                username: admin.username,
                displayName: admin.displayName.isEmpty ? admin.username : admin.displayName,
                avatar: admin.avatar,
                lastUsedAt: Date()
            ),
            at: 0
        )

        while next.count > maxProfiles {
            if let oldest = next.last {
                KeychainStore.deletePassword(account: oldest.id)
                next.removeLast()
            }
        }

        persist(next)
    }

    func password(for id: String) -> String? {
        KeychainStore.password(account: id)
    }

    /// Keep a saved profile's display name / avatar in sync after a profile edit
    /// (does not touch the stored password used for biometric login).
    func updateProfileInfo(id: String, displayName: String, avatar: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var next = profiles
        let old = next[index]
        next[index] = SavedLoginProfile(
            id: old.id,
            username: old.username,
            displayName: displayName.isEmpty ? old.username : displayName,
            avatar: avatar,
            lastUsedAt: old.lastUsedAt
        )
        persist(next)
    }

    /// Update the stored password for a saved profile after a password change so
    /// Face ID / Touch ID login keeps working.
    func updatePassword(id: String, password: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        KeychainStore.setPassword(password, account: id)
    }

    func remove(id: String) {
        KeychainStore.deletePassword(account: id)
        persist(profiles.filter { $0.id != id })
    }

    func touch(id: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var next = profiles
        next[index].lastUsedAt = Date()
        next.sort { $0.lastUsedAt > $1.lastUsedAt }
        persist(next)
    }

    private func load() -> [SavedLoginProfile] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedLoginProfile].self, from: data)
        else { return [] }
        return decoded.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    private func persist(_ value: [SavedLoginProfile]) {
        profiles = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
