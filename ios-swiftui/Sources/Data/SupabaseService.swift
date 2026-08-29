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

/// Lightweight row used for ID-index reconcile (no transaction body).
struct TransactionIndexRow: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
    }
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

    /// Columns required by `Transaction` decoding — mirrors Flutter `_transactionColumns`
    /// to cut Disk IO / JSON payload vs `select(*)`.
    static let transactionSelectColumns =
        "id, date, type, category, description, amount, quantity, unit, note, "
        + "sub_category, created_at, updated_at, employee_id, employee_ids, "
        + "driver_id, driver_wage, vehicle_wage, vehicle_id, vehicle_name, "
        + "unit_price, project_id, labor_status, work_type, work_type_by_employee, "
        + "work_assignments, ot_amount, advance_amount, special_amount, ot_hours, "
        + "leave_reason, leave_days, work_details, fuel_type, fuel_movement, fuel_tank, "
        + "machine_id, machine_hours, trip_count, trip_morning, trip_afternoon, "
        + "trip_billing_mode, cubic_per_trip, total_cubic, per_car_trips, per_car_cubic, "
        + "sand_morning, sand_afternoon, sand_machine_type, sand_operators, sand_transport, "
        + "drums_obtained, drums_washed_at_home, sand_batch_id, "
        + "event_type, event_priority, event_time, income_payment_status"

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

    /// Recent transactions only (default ≈90 days) so analytics stay light.
    /// Uses a projected column list to cut Disk IO / payload vs `select(*)`.
    /// - Parameters:
    ///   - daysBack: Inclusive lookback from today (Bangkok). Use 14 for cold-start.
    ///   - limit: Max rows (newest first).
    func fetchTransactions(daysBack: Int = 90, limit: Int = 2000) async throws -> TransactionFetchResult {
        let since = Self.transactionsWindowStartYMD(daysBack: daysBack)
        let data: Data
        do {
            data = try await client.from("transactions")
                .select(Self.transactionSelectColumns)
                .gte("date", value: since)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .data
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
        return await Task.detached(priority: .userInitiated) {
            Self.decodeTransactions(from: data)
        }.value
    }

    /// Gregorian YMD N days ago (Bangkok calendar), used to bound the main fetch.
    nonisolated static func transactionsWindowStartYMD(daysBack: Int = 90) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        let start = cal.date(byAdding: .day, value: -max(0, daysBack), to: Date()) ?? Date()
        let y = cal.component(.year, from: start)
        let m = cal.component(.month, from: start)
        let d = cal.component(.day, from: start)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Delta fetch: only rows changed since `isoTimestamp` (bounded to the 90-day window).
    func fetchTransactionsSince(_ isoTimestamp: String) async throws -> TransactionFetchResult {
        let since = Self.transactionsWindowStartYMD(daysBack: 90)
        let data: Data
        do {
            data = try await client.from("transactions")
                .select(Self.transactionSelectColumns)
                .gte("date", value: since)
                .gt("updated_at", value: isoTimestamp)
                .order("updated_at", ascending: false)
                .limit(500)
                .execute()
                .data
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
        return await Task.detached(priority: .userInitiated) {
            Self.decodeTransactions(from: data)
        }.value
    }

    /// Lightweight index for reconcile: ids + updated_at in the 90-day window (no row body).
    func fetchTransactionIndex() async throws -> [TransactionIndexRow] {
        let since = Self.transactionsWindowStartYMD(daysBack: 90)
        do {
            return try await client.from("transactions")
                .select("id,updated_at")
                .gte("date", value: since)
                .order("updated_at", ascending: false)
                .limit(2000)
                .execute()
                .value
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }

    /// Fetches full transaction bodies for the given ids (chunked for PostgREST URL limits).
    func fetchTransactions(ids: [String]) async throws -> TransactionFetchResult {
        let unique = Array(Set(ids)).filter { !$0.isEmpty }
        guard !unique.isEmpty else {
            return TransactionFetchResult(transactions: [], skippedCount: 0)
        }

        var all: [Transaction] = []
        var skipped = 0
        let chunkSize = 100
        var start = 0
        while start < unique.count {
            let end = min(start + chunkSize, unique.count)
            let chunk = Array(unique[start..<end])
            let data: Data
            do {
                data = try await client.from("transactions")
                    .select(Self.transactionSelectColumns)
                    .in("id", values: chunk)
                    .execute()
                    .data
            } catch {
                throw DataServiceError.fetchFailed(error.localizedDescription)
            }
            let part = await Task.detached(priority: .userInitiated) {
                Self.decodeTransactions(from: data)
            }.value
            all.append(contentsOf: part.transactions)
            skipped += part.skippedCount
            start = end
        }
        return TransactionFetchResult(transactions: all, skippedCount: skipped)
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
        async let settingsTask: [AppSettingsRow] = client.from("app_settings")
            .select()
            .eq("id", value: "default")
            .limit(1)
            .execute()
            .value
        let rows = try await settingsTask
        let catalog: [VehicleCatalogRow]
        do {
            let data = try await client.from("vehicles")
                .select("id, name, default_driver_id, sort_order")
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute()
                .data
            let items = (try? JSONDecoder().decode([FailableDecodable<VehicleCatalogRow>].self, from: data)) ?? []
            catalog = items.compactMap(\.value).filter {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        } catch {
            catalog = []
        }
        return rows.first?.toAppSettings(vehicleCatalog: catalog) ?? .fallback
    }

    /// Inserts one diagnostic row (crash / hang / runtime error) into `mobile_error_reports`.
    func submitErrorReport(_ row: MobileErrorReportInsert) async throws {
        _ = try await client.from("mobile_error_reports")
            .insert(row)
            .execute()
    }

    // MARK: - Tasks (เมนู "งาน")

    /// All task rows, newest due date first. Visibility is filtered app-side in `TaskStore`.
    func fetchTasks() async throws -> [WorkTask] {
        do {
            return try await client.from("tasks")
                .select()
                .order("due_date", ascending: false)
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func upsertTask(_ task: WorkTask) async throws {
        do {
            _ = try await client.from("tasks")
                .upsert(task, onConflict: "id")
                .execute()
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func deleteTask(id: String) async throws {
        do {
            _ = try await client.from("tasks")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Transactions (count-record writes)

    /// Upserts a DailyLog trip/sand row and returns the stored transaction.
    func upsertTransaction(_ payload: TransactionWritePayload) async throws -> Transaction {
        do {
            let data = try await client.from("transactions")
                .upsert(payload, onConflict: "id")
                .select()
                .single()
                .execute()
                .data
            return try Self.jsonDecoder.decode(Transaction.self, from: data)
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func deleteTransaction(id: String) async throws {
        do {
            _ = try await client.from("transactions")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            throw DataServiceError.fetchFailed(error.localizedDescription)
        }
    }
}
