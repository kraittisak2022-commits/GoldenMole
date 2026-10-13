import Foundation
import Observation

// MARK: - Models (mirror apps/photo/shared/types.ts)

struct PhotoMediaSources: Decodable, Hashable, Sendable {
    /// Grid size (longest side ~640px).
    let thumb: String
    /// Tried when `thumb` fails.
    let thumbFallback: String
    /// Viewer size for images; poster for videos.
    let large: String
    let download: String
    /// Embeddable Drive player, videos only.
    let preview: String?
}

struct PhotoMediaItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let name: String
    let width: Int
    let height: Int
    let takenAt: String?
    let createdAt: String
    let uploadedByName: String?
    let src: PhotoMediaSources

    var isVideo: Bool { kind == "video" }
}

struct PhotoAlbumSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// YYYY-MM-DD
    let reportDate: String
    let mediaCount: Int
    let cover: PhotoMediaSources?
    let shareUrl: String
    let driveFolderUrl: String
}

struct PhotoAlbumDetail: Decodable, Sendable {
    let id: String
    let title: String
    let reportDate: String
    let mediaCount: Int
    let shareUrl: String
    let driveFolderUrl: String
    let media: [PhotoMediaItem]
}

enum PhotoAlbumError: LocalizedError, Equatable {
    case needsPassword
    case unauthorized
    case badCredentials
    case forbidden
    case tooManyAttempts
    case notFound
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .needsPassword, .unauthorized: return "กรุณาเข้าสู่ระบบอัลบั้ม"
        case .badCredentials: return "รหัสผ่านไม่ถูกต้อง"
        case .forbidden: return "บัญชีนี้ไม่มีสิทธิ์ดูอัลบั้ม — ขอสิทธิ์ «อัลบั้มรูป» จาก SuperAdmin"
        case .tooManyAttempts: return "ใส่รหัสผิดหลายครั้ง — รอ 15 นาทีแล้วลองใหม่"
        case .notFound: return "ไม่พบอัลบั้มนี้ (อาจถูกลบแล้ว)"
        case .network(let detail): return "เชื่อมต่อ GoldenMole Photos ไม่ได้ — \(detail)"
        case .server(let code): return "GoldenMole Photos ขัดข้อง (\(code))"
        }
    }
}

// MARK: - API (photo.goldenmole.pro Vercel functions)

enum PhotoAlbumAPI {
    static let webURL = URL(string: "https://photo.goldenmole.pro")!
    private static let apiURL = webURL.appendingPathComponent("api")

    private struct ErrorBody: Decodable { let error: String }
    private struct TokenBody: Decodable { let token: String }

    static func login(username: String, password: String) async throws -> String {
        var request = URLRequest(url: apiURL.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])
        let body: TokenBody = try await send(request)
        return body.token
    }

    /// Returns a renewed session token (the server extends it by 30 days).
    static func renew(token: String) async throws -> String {
        let body: TokenBody = try await send(authorized(path: "auth/me", token: token))
        return body.token
    }

    static func albums(token: String) async throws -> [PhotoAlbumSummary] {
        try await send(authorized(path: "albums", token: token))
    }

    static func album(id: String, token: String) async throws -> PhotoAlbumDetail {
        try await send(authorized(path: "albums/\(id)", token: token))
    }

    private static func authorized(path: String, token: String) -> URLRequest {
        var request = URLRequest(url: apiURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = 20
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw PhotoAlbumError.network(error.localizedDescription)
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "http_\(status)"
            switch code {
            case "bad_credentials": throw PhotoAlbumError.badCredentials
            case "unauthorized": throw PhotoAlbumError.unauthorized
            case "forbidden": throw PhotoAlbumError.forbidden
            case "too_many_attempts": throw PhotoAlbumError.tooManyAttempts
            case "not_found": throw PhotoAlbumError.notFound
            default: throw PhotoAlbumError.server(code)
            }
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PhotoAlbumError.server("decode")
        }
    }
}

// MARK: - Session (photo-site token per admin, kept in the Keychain)

@MainActor
@Observable
final class PhotoAlbumSession {
    static let shared = PhotoAlbumSession()

    private static let keychainService = "com.goldenmole.dashboard.photo-session"
    @ObservationIgnored private var renewedAdminIds: Set<String> = []

    private init() {}

    /// Best effort right after the main app login, so the album tab opens without asking again.
    func prefetchToken(adminId: String, username: String, password: String) async {
        guard storedToken(adminId: adminId) == nil else { return }
        if let token = try? await PhotoAlbumAPI.login(username: username, password: password) {
            store(token, adminId: adminId)
        }
    }

    func signIn(admin: AdminUser, password: String) async throws {
        let token = try await PhotoAlbumAPI.login(username: admin.username, password: password)
        store(token, adminId: admin.id)
    }

    func signOut(adminId: String) {
        KeychainStore.deletePassword(account: adminId, service: Self.keychainService)
        renewedAdminIds.remove(adminId)
    }

    /// Runs `call` with a valid token; on 401 drops the stale token and retries once.
    func withToken<T>(admin: AdminUser, _ call: (String) async throws -> T) async throws -> T {
        let token = try await token(for: admin)
        do {
            return try await call(token)
        } catch PhotoAlbumError.unauthorized {
            signOut(adminId: admin.id)
            return try await call(try await token(for: admin))
        }
    }

    private func token(for admin: AdminUser) async throws -> String {
        if let token = storedToken(adminId: admin.id) {
            if !renewedAdminIds.contains(admin.id),
               let renewed = try? await PhotoAlbumAPI.renew(token: token) {
                renewedAdminIds.insert(admin.id)
                store(renewed, adminId: admin.id)
                return renewed
            }
            return token
        }
        guard let password = SavedProfilesStore.shared.password(for: admin.id) else {
            throw PhotoAlbumError.needsPassword
        }
        do {
            let token = try await PhotoAlbumAPI.login(username: admin.username, password: password)
            store(token, adminId: admin.id)
            return token
        } catch PhotoAlbumError.badCredentials {
            throw PhotoAlbumError.needsPassword
        }
    }

    private func storedToken(adminId: String) -> String? {
        KeychainStore.password(account: adminId, service: Self.keychainService)
    }

    private func store(_ token: String, adminId: String) {
        KeychainStore.setPassword(token, account: adminId, service: Self.keychainService)
    }
}
