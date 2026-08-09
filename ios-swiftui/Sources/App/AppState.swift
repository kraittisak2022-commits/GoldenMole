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

    /// True after a successful disk hydrate (even if arrays stay empty).
    private(set) var didHydrateFromCache = false

    @ObservationIgnored private var dataService: SupabaseService?
    @ObservationIgnored private var syncCoordinator: RealtimeSyncCoordinator?
    @ObservationIgnored private var cacheMeta: LocalDataCache.Meta?
    @ObservationIgnored private var cachePersistTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var suppressCachePersist = false

    /// Newest `updated_at` currently held — used as the delta-poll cursor.
    var maxTransactionUpdatedAt: String? {
        transactions.compactMap(\.updatedAt).max() ?? cacheMeta?.maxUpdatedAt
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

    /// Cache younger than 2 minutes — prefer delta over full transaction fetch.
    var hasFreshTransactionCache: Bool {
        LocalDataCache.isWithinTTL(cacheMeta?.transactionsSavedAt ?? lastFetchedAt, ttl: LocalDataCache.transactionsFreshTTL)
            && !transactions.isEmpty
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
        await hydrateFromCacheIfNeeded()
        await refresh()
    }

    // MARK: - Disk cache

    func hydrateFromCacheIfNeeded() async {
        guard !didHydrateFromCache else { return }
        didHydrateFromCache = true
        guard let snap = await LocalDataCache.loadSnapshot() else { return }

        cacheMeta = snap.meta
        if transactions.isEmpty, !snap.transactions.isEmpty {
            transactions = snap.transactions
            transactionsRevision += 1
            lastFetchTransactionCount = snap.transactions.count
            lastFetchedAt = snap.meta.transactionsSavedAt
        }
        if employees.isEmpty, !snap.employees.isEmpty {
            employees = snap.employees
            lastFetchEmployeeCount = snap.employees.count
        }
        // First hydrate wins for settings when we have not network-refreshed yet.
        settings = snap.settings
    }

    private func scheduleCachePersist() {
        cachePersistTask?.cancel()
        cachePersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.persistCacheNow()
        }
    }

    private func persistCacheNow() async {
        let tx = transactions
        let emp = employees
        let set = settings
        await LocalDataCache.saveSnapshot(transactions: tx, employees: emp, settings: set)
        cacheMeta = LocalDataCache.Meta(
            savedAt: Date(),
            transactionCount: tx.count,
            employeeCount: emp.count,
            maxUpdatedAt: tx.compactMap(\.updatedAt).max(),
            transactionsSavedAt: Date(),
            employeesSavedAt: Date(),
            settingsSavedAt: Date()
        )
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
        if !suppressCachePersist {
            scheduleCachePersist()
        }
    }

    func removeTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        transactions.remove(at: idx)
        transactionsRevision += 1
        lastFetchTransactionCount = transactions.count
        lastFetchedAt = Date()
        if !suppressCachePersist {
            scheduleCachePersist()
        }
    }

    /// Merges delta rows into the in-memory list (by id).
    func applyTransactionDelta(_ rows: [Transaction]) {
        guard !rows.isEmpty else { return }
        suppressCachePersist = true
        for tx in rows {
            upsertTransaction(tx)
        }
        suppressCachePersist = false
        scheduleCachePersist()
    }

    /// - Parameter forceFull: when true, always full-fetch transactions (and roster).
    func refresh(forceFull: Bool = false) async {
        guard let dataService else { return }
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await hydrateFromCacheIfNeeded()

        // Only show the blocking spinner when we still have nothing to show.
        let shouldShowLoading = transactions.isEmpty
        if isLoading != shouldShowLoading { isLoading = shouldShowLoading }
        var errors: [String] = []
        var didMutateData = false

        // --- Transactions ---
        do {
            let preferDelta = !forceFull
                && hasFreshTransactionCache
                && (maxTransactionUpdatedAt?.isEmpty == false)

            if preferDelta, let since = maxTransactionUpdatedAt {
                let result = try await dataService.fetchTransactionsSince(since)
                if !result.transactions.isEmpty {
                    applyTransactionDelta(result.transactions)
                    didMutateData = true
                }
                lastSkippedTransactionCount = result.skippedCount
                lastFetchedAt = Date()
                lastFetchTransactionCount = transactions.count
            } else {
                let fetchResult = try await dataService.fetchTransactions()
                if transactions != fetchResult.transactions {
                    transactions = fetchResult.transactions
                    transactionsRevision += 1
                    didMutateData = true
                }
                lastFetchTransactionCount = fetchResult.transactions.count
                lastSkippedTransactionCount = fetchResult.skippedCount
                lastFetchedAt = Date()
            }
        } catch {
            errors.append("transactions: \(error.localizedDescription)")
        }

        // --- Employees ---
        let employeesFresh = !forceFull
            && LocalDataCache.isWithinTTL(cacheMeta?.employeesSavedAt, ttl: LocalDataCache.rosterTTL)
            && !employees.isEmpty
        if !employeesFresh {
            do {
                let e = try await dataService.fetchEmployees()
                if employees != e {
                    employees = e
                    didMutateData = true
                }
                lastFetchEmployeeCount = e.count
            } catch {
                errors.append("employees: \(error.localizedDescription)")
            }
        } else {
            lastFetchEmployeeCount = employees.count
        }

        // --- Settings ---
        let settingsFresh = !forceFull
            && LocalDataCache.isWithinTTL(cacheMeta?.settingsSavedAt, ttl: LocalDataCache.rosterTTL)
            && settings != .fallback
        if !settingsFresh {
            do {
                let s = try await dataService.fetchSettings()
                if settings != s {
                    settings = s
                    didMutateData = true
                }
            } catch {
                errors.append("settings: \(error.localizedDescription)")
            }
        }

        if transactions.isEmpty && !errors.isEmpty {
            errorMessage = errors.joined(separator: " · ")
            ErrorReportCenter.shared.reportMessage(
                "โหลดข้อมูลไม่สำเร็จ (ไม่มีข้อมูลแสดง)",
                detail: errors.joined(separator: "\n"),
                source: "error",
                screenPage: String(describing: selectedTab)
            )
        } else if !errors.isEmpty && !transactions.isEmpty {
            errorMessage = errors.joined(separator: " · ")
        } else {
            errorMessage = nil
        }

        if isLoading { isLoading = false }

        // Persist after a successful network pass (or when we mutated via delta).
        if errors.isEmpty || didMutateData || (!transactions.isEmpty && cacheMeta == nil) {
            await persistCacheNow()
        }
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
