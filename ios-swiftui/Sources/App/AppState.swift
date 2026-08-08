import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    var transactions: [Transaction] = []
    var employees: [Employee] = []
    var settings: AppSettings = .fallback
    var isLoading = false
    var errorMessage: String?
    var selectedTab: DashboardTab = .realtimeV4
    var datePreset: DateRangePreset = .days7
    var customStart = DashboardAggregations.gregorian.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    var customEnd = Date()

    /// AI market insights (gold + oil). Loaded lazily when the tab opens; independent of transactions sync.
    var marketInsight: MarketInsightSnapshot?
    var marketLoading = false
    var marketError: String?

    /// Diagnostics: last successful fetch sizes / skip counts.
    var lastFetchTransactionCount = 0
    var lastFetchEmployeeCount = 0
    var lastSkippedTransactionCount = 0
    var lastFetchedAt: Date?
    var supabaseHost: String = SupabaseConfig.isConfigured ? SupabaseConfig.host : "(ยังไม่ตั้งค่า)"

    @ObservationIgnored private var dataService: SupabaseService?
    @ObservationIgnored private var syncCoordinator: RealtimeSyncCoordinator?

    /// Newest `updated_at` currently held — used as the delta-poll cursor.
    var maxTransactionUpdatedAt: String? {
        transactions.compactMap(\.updatedAt).max()
    }

    /// Bumped on every transactions mutation so views can avoid Equatable-diffing the full array.
    private(set) var transactionsRevision = 0

    var dateFilter: DateFilter {
        DashboardAggregations.dateFilter(preset: datePreset, customStart: customStart, customEnd: customEnd)
    }

    var filteredTransactions: [Transaction] {
        DashboardAggregations.filterByRange(transactions, range: dateFilter)
    }

    /// True after a successful transactions fetch that returned zero rows (not a network/decode failure).
    var hasEmptySuccessfulFetch: Bool {
        lastFetchedAt != nil && errorMessage == nil && transactions.isEmpty
    }

    func configure(dataService: SupabaseService) {
        self.dataService = dataService
        supabaseHost = SupabaseConfig.host
        syncCoordinator?.stop()
        let coordinator = RealtimeSyncCoordinator(service: dataService, appState: self)
        syncCoordinator = coordinator
        coordinator.start()
        CountRecordOfflineSync.shared.configure(service: dataService, appState: self)
    }

    func loadInitial() async {
        await refresh()
    }

    // MARK: - Incremental realtime apply

    /// Inserts or replaces a transaction by id, keeping the list ordered by created_at desc.
    /// New rows use sorted insertion (O(n)) instead of re-sorting the whole array.
    func upsertTransaction(_ tx: Transaction) {
        if let idx = transactions.firstIndex(where: { $0.id == tx.id }) {
            if transactions[idx] != tx {
                transactions[idx] = tx
                transactionsRevision += 1
            }
        } else {
            let key = tx.createdAt ?? ""
            // List is newest-first; insert before the first older row.
            let insertAt = transactions.firstIndex { ($0.createdAt ?? "") < key } ?? transactions.count
            transactions.insert(tx, at: insertAt)
            transactionsRevision += 1
        }
        lastFetchTransactionCount = transactions.count
        lastFetchedAt = Date()
    }

    func removeTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        transactions.remove(at: idx)
        transactionsRevision += 1
        lastFetchTransactionCount = transactions.count
        lastFetchedAt = Date()
    }

    func refresh() async {
        guard let dataService else { return }
        // Only show the blocking spinner on the very first load; reconciles stay silent
        // to avoid invalidating views that observe `isLoading`.
        let shouldShowLoading = transactions.isEmpty
        if isLoading != shouldShowLoading { isLoading = shouldShowLoading }
        var errors: [String] = []

        // Fetch independently so one failing endpoint cannot blank the whole app.
        do {
            let fetchResult = try await dataService.fetchTransactions()
            // Only reassign when data actually changed so periodic reconciles don't
            // re-render the whole dashboard when nothing is new.
            if transactions != fetchResult.transactions {
                transactions = fetchResult.transactions
                transactionsRevision += 1
            }
            lastFetchTransactionCount = fetchResult.transactions.count
            lastSkippedTransactionCount = fetchResult.skippedCount
            lastFetchedAt = Date()
        } catch {
            errors.append("transactions: \(error.localizedDescription)")
        }

        do {
            let e = try await dataService.fetchEmployees()
            if employees != e {
                employees = e
            }
            lastFetchEmployeeCount = e.count
        } catch {
            errors.append("employees: \(error.localizedDescription)")
        }

        do {
            let s = try await dataService.fetchSettings()
            if settings != s {
                settings = s
            }
        } catch {
            errors.append("settings: \(error.localizedDescription)")
        }

        if transactions.isEmpty && !errors.isEmpty {
            errorMessage = errors.joined(separator: " · ")
            // Critical: app has no data because every source failed. Report it (deduped/rate-limited).
            ErrorReportCenter.shared.reportMessage(
                "โหลดข้อมูลไม่สำเร็จ (ไม่มีข้อมูลแสดง)",
                detail: errors.joined(separator: "\n"),
                source: "error",
                screenPage: String(describing: selectedTab)
            )
        } else if !errors.isEmpty && transactions.isEmpty == false {
            // Soft warning — keep data, surface issue in Profile diagnostics
            errorMessage = errors.joined(separator: " · ")
        } else {
            errorMessage = nil
        }

        if isLoading { isLoading = false }
    }

    /// Loads the latest market insight row. Safe to call repeatedly (tab appear / manual refresh).
    func loadMarket() async {
        guard let dataService else { return }
        marketLoading = true
        marketError = nil
        do {
            marketInsight = try await dataService.fetchMarketInsights()
        } catch {
            marketError = error.localizedDescription
        }
        marketLoading = false
    }

    /// Supabase client for online count-record writes (nil when not configured).
    var supabaseService: SupabaseService? { dataService }
}
