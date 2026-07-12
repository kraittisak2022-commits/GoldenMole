import Foundation
import Supabase

enum DataServiceError: LocalizedError {
    case notConfigured
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "ยังไม่ได้ตั้งค่า Supabase"
        case .fetchFailed(let msg): return msg
        }
    }
}

@MainActor
final class SupabaseService: ObservableObject {
    private let client: SupabaseClient

    init() throws {
        guard SupabaseConfig.isConfigured else { throw DataServiceError.notConfigured }
        client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey)
    }

    func fetchAdmins() async throws -> [AdminUser] {
        try await client.from("admin_users")
            .select()
            .order("created_at")
            .execute()
            .value
    }

    func updateAdminLastLogin(id: String) async {
        let payload: [String: String] = ["last_login": ISO8601DateFormatter().string(from: Date())]
        _ = try? await client.from("admin_users")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    func fetchTransactions() async throws -> [Transaction] {
        try await client.from("transactions")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchEmployees() async throws -> [Employee] {
        try await client.from("employees")
            .select()
            .order("created_at")
            .execute()
            .value
    }

    func fetchSettings() async throws -> AppSettings {
        let rows: [AppSettingsRow] = try await client.from("app_settings")
            .select()
            .eq("id", value: "default")
            .limit(1)
            .execute()
            .value
        return rows.first?.toAppSettings() ?? .fallback
    }

    /// Polls every 12s (matches web dashboard refresh cadence). Realtime channel can be enabled on device builds.
    func subscribeToTransactions(onChange: @escaping () -> Void) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await MainActor.run { onChange() }
            }
        }
    }
}
