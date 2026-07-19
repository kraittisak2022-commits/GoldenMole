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

struct TransactionFetchResult: Sendable {
    let transactions: [Transaction]
    let skippedCount: Int
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

    /// Fetches transactions and decodes row-by-row so one bad row cannot wipe the whole dataset.
    func fetchTransactions() async throws -> TransactionFetchResult {
        let data: Data
        do {
            data = try await client.from("transactions")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .data
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }

        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw DataServiceError.fetchFailed("รูปแบบข้อมูล transactions ไม่ถูกต้อง")
        }

        let decoder = JSONDecoder()
        var decoded: [Transaction] = []
        var skipped = 0
        decoded.reserveCapacity(rows.count)

        for row in rows {
            guard JSONSerialization.isValidJSONObject(row),
                  let rowData = try? JSONSerialization.data(withJSONObject: row),
                  let tx = try? decoder.decode(Transaction.self, from: rowData)
            else {
                skipped += 1
                continue
            }
            decoded.append(tx)
        }

        return TransactionFetchResult(transactions: decoded, skippedCount: skipped)
    }

    func fetchEmployees() async throws -> [Employee] {
        try await client.from("employees")
            .select()
            .order("created_at")
            .execute()
            .value
    }

    /// Latest AI market insight row (gold + oil). Returns nil when the table is empty.
    func fetchMarketInsights() async throws -> MarketInsightSnapshot? {
        let rows: [MarketInsightSnapshot]
        do {
            rows = try await client.from("market_insights")
                .select("generated_at,status,payload")
                .order("generated_at", ascending: false)
                .limit(1)
                .execute()
                .value
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
        return rows.first
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

    /// Polls every 12s (matches web dashboard refresh cadence). Fires once immediately.
    func subscribeToTransactions(onChange: @escaping () -> Void) -> Task<Void, Never> {
        Task {
            await MainActor.run { onChange() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run { onChange() }
            }
        }
    }
}
