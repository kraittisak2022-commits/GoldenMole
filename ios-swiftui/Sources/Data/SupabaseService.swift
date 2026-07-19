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

/// Lossy element: decodes T when possible, otherwise keeps nil so one bad row
/// never aborts decoding of the whole array.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
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

    /// Updates editable admin_users columns (display_name / avatar / password) for one admin.
    func updateAdminProfile(id: String, fields: [String: String]) async throws {
        guard !fields.isEmpty else { return }
        do {
            try await client.from("admin_users")
                .update(fields)
                .eq("id", value: id)
                .execute()
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func updateAdminLastLogin(id: String) async {
        let payload: [String: String] = ["last_login": ISO8601DateFormatter().string(from: Date())]
        _ = try? await client.from("admin_users")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    /// Shared decoder — reused instead of allocating one per fetch.
    private nonisolated static let jsonDecoder = JSONDecoder()

    /// Decodes a single transaction (used for realtime record payloads).
    nonisolated static func decodeSingleTransaction(from data: Data) -> Transaction? {
        try? jsonDecoder.decode(Transaction.self, from: data)
    }

    /// Decodes an array of transactions off the caller's actor, skipping malformed rows.
    /// Runs on a background executor because it is `nonisolated`.
    nonisolated static func decodeTransactions(from data: Data) -> TransactionFetchResult {
        let items = (try? jsonDecoder.decode([FailableDecodable<Transaction>].self, from: data)) ?? []
        var decoded: [Transaction] = []
        decoded.reserveCapacity(items.count)
        var skipped = 0
        for item in items {
            if let value = item.value { decoded.append(value) } else { skipped += 1 }
        }
        return TransactionFetchResult(transactions: decoded, skippedCount: skipped)
    }

    /// Fetches all transactions. Network runs here; decoding is offloaded off the main actor
    /// (`Task.detached`) so large payloads never block the UI.
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
        return await Task.detached(priority: .userInitiated) {
            Self.decodeTransactions(from: data)
        }.value
    }

    /// Delta fetch: only rows changed since `isoTimestamp` (used by the realtime fallback poll).
    func fetchTransactionsSince(_ isoTimestamp: String) async throws -> TransactionFetchResult {
        let data: Data
        do {
            data = try await client.from("transactions")
                .select()
                .gt("updated_at", value: isoTimestamp)
                .order("created_at", ascending: false)
                .execute()
                .data
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
        return await Task.detached(priority: .userInitiated) {
            Self.decodeTransactions(from: data)
        }.value
    }

    /// A realtime channel for the given topic (used by RealtimeSyncCoordinator).
    func realtimeChannel(_ topic: String) -> RealtimeChannelV2 {
        client.channel(topic)
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

    /// Inserts one diagnostic row (crash / hang / runtime error) into `mobile_error_reports`.
    func submitErrorReport(_ row: MobileErrorReportInsert) async throws {
        _ = try await client.from("mobile_error_reports")
            .insert(row)
            .execute()
    }

}
