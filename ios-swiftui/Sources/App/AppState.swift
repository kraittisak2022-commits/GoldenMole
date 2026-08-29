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
    var datePreset: DateRangePreset = .today
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
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var suppressCachePersist = false
    @ObservationIgnored private var lastForegroundRefreshAt: Date?
    @ObservationIgnored private var lastReconcileAt: Date?

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

    /// Clears in-memory + disk cache (logout).
    func clearLocalData() {
        cachePersistTask?.cancel()
        cachePersistTask = nil
        transactions = []
        employees = []
        settings = .fallback
        transactionsRevision += 1
        cacheMeta = nil
        didHydrateFromCache = false
        lastFetchedAt = nil
        lastReconcileAt = nil
        lastForegroundRefreshAt = nil
        lastFetchTransactionCount = 0
        lastFetchEmployeeCount = 0
        LocalDataCache.invalidate()
    }

    // MARK: - Disk cache

    func hydrateFromCacheIfNeeded() async {
        guard !didHydrateFromCache else { return }
        didHydrateFromCache = true
        guard let snap = await LocalDataCache.loadSnapshot() else { return }

        cacheMeta = snap.meta
        lastReconcileAt = snap.meta.lastReconcileAt
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
            await self.persistTransactionsOnly()
        }
    }

    private func persistTransactionsOnly() async {
        cacheMeta = await LocalDataCache.saveTransactions(
            transactions,
            preserving: cacheMeta,
            lastReconcileAt: lastReconcileAt
        )
    }

    private func persistEmployeesOnly() async {
        cacheMeta = await LocalDataCache.saveEmployees(employees, preserving: cacheMeta)
    }

    private func persistSettingsOnly() async {
        cacheMeta = await LocalDataCache.saveSettings(settings, preserving: cacheMeta)
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

    // MARK: - ID-index reconcile (detect remote deletes + missed updates)

    /// Compares a lightweight server index (`id,updated_at`) with memory; removes ghosts and
    /// fetches only bodies that are missing or newer. Much cheaper than a full 2000-row body fetch.
    func reconcileTransactionsWithIndex() async {
        guard let dataService else { return }
        if isReconciling { return }
        isReconciling = true
        defer { isReconciling = false }

        do {
            let index = try await dataService.fetchTransactionIndex()
            let windowStart = SupabaseService.transactionsWindowStartYMD()
            var remoteById: [String: TransactionIndexRow] = [:]
            remoteById.reserveCapacity(index.count)
            for row in index { remoteById[row.id] = row }
            let remoteIds = Set(remoteById.keys)

            // Remove local rows in the window that no longer exist remotely.
            var removed = false
            suppressCachePersist = true
            let ghostIds = transactions
                .filter { $0.date >= windowStart && !remoteIds.contains($0.id) }
                .map(\.id)
            for id in ghostIds {
                removeTransaction(id: id)
                removed = true
            }

            // Fetch bodies for missing or newer rows.
            var staleIds: [String] = []
            var localById: [String: Transaction] = [:]
            localById.reserveCapacity(transactions.count)
            for tx in transactions { localById[tx.id] = tx }
            for row in index {
                if let local = localById[row.id] {
                    let remoteUpdated = row.updatedAt ?? ""
                    let localUpdated = local.updatedAt ?? ""
                    if !remoteUpdated.isEmpty, remoteUpdated > localUpdated {
                        staleIds.append(row.id)
                    }
                } else {
                    staleIds.append(row.id)
                }
            }
            suppressCachePersist = false

            if !staleIds.isEmpty {
                let result = try await dataService.fetchTransactions(ids: staleIds)
                if !result.transactions.isEmpty {
                    applyTransactionDelta(result.transactions)
                }
                lastSkippedTransactionCount = result.skippedCount
            } else if removed {
                scheduleCachePersist()
            }

            lastReconcileAt = Date()
            lastFetchedAt = Date()
            lastFetchTransactionCount = transactions.count
            // Persist meta with reconcile timestamp even when nothing mutated.
            cacheMeta = await LocalDataCache.saveTransactions(
                transactions,
                preserving: cacheMeta,
                lastReconcileAt: lastReconcileAt
            )
        } catch {
            // Transient — next cycle / foreground will retry.
        }
    }

    /// Delta sync when returning to foreground; runs ID-index reconcile if due (~10 min).
    func refreshOnForeground() async {
        // Debounce rapid app-switch chatter.
        if let last = lastForegroundRefreshAt, Date().timeIntervalSince(last) < 2 {
            return
        }
        lastForegroundRefreshAt = Date()

        await hydrateFromCacheIfNeeded()
        await refresh(forceFull: false)

        let reconcileDue = !LocalDataCache.isWithinTTL(
            lastReconcileAt ?? cacheMeta?.lastReconcileAt,
            ttl: LocalDataCache.reconcileTTL
        )
        if reconcileDue {
            await reconcileTransactionsWithIndex()
        }
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
        var didRefreshTransactions = false
        var didRefreshEmployees = false
        var didRefreshSettings = false

        // --- Transactions ---
        do {
            let preferDelta = !forceFull
                && hasFreshTransactionCache
                && (maxTransactionUpdatedAt?.isEmpty == false)

            if preferDelta, let since = maxTransactionUpdatedAt {
                let result = try await dataService.fetchTransactionsSince(since)
                if !result.transactions.isEmpty {
                    applyTransactionDelta(result.transactions)
                }
                lastSkippedTransactionCount = result.skippedCount
                lastFetchedAt = Date()
                lastFetchTransactionCount = transactions.count
            } else {
                let fetchResult = try await dataService.fetchTransactions()
                if transactions != fetchResult.transactions {
                    transactions = fetchResult.transactions
                    transactionsRevision += 1
                }
                lastFetchTransactionCount = fetchResult.transactions.count
                lastSkippedTransactionCount = fetchResult.skippedCount
                lastFetchedAt = Date()
                // Full body replace already matches the server window — skip immediate index reconcile.
                lastReconcileAt = Date()
            }
            didRefreshTransactions = true
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
                }
                lastFetchEmployeeCount = e.count
                didRefreshEmployees = true
            } catch {
                errors.append("employees: \(error.localizedDescription)")
            }
        } else {
            lastFetchEmployeeCount = employees.count
        }

        // --- Settings (re-fetch when vehicle catalog missing so v_ ids can resolve) ---
        let settingsFresh = !forceFull
            && LocalDataCache.isWithinTTL(cacheMeta?.settingsSavedAt, ttl: LocalDataCache.rosterTTL)
            && settings != .fallback
            && !settings.vehicleCatalog.isEmpty
        if !settingsFresh {
            do {
                let s = try await dataService.fetchSettings()
                if settings != s {
                    settings = s
                }
                didRefreshSettings = true
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

        // Domain-scoped persist so tx writes do not inflate roster TTLs.
        if didRefreshTransactions {
            await persistTransactionsOnly()
        }
        if didRefreshEmployees {
            await persistEmployeesOnly()
        }
        if didRefreshSettings {
            await persistSettingsOnly()
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
