import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var employees: [Employee] = []
    @Published var settings: AppSettings = .fallback
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: DashboardTab = .realtimeV4
    @Published var datePreset: DateRangePreset = .days7
    @Published var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @Published var customEnd = Date()

    /// Diagnostics: last successful fetch sizes / skip counts.
    @Published var lastFetchTransactionCount = 0
    @Published var lastFetchEmployeeCount = 0
    @Published var lastSkippedTransactionCount = 0
    @Published var lastFetchedAt: Date?
    @Published var supabaseHost: String = SupabaseConfig.isConfigured ? SupabaseConfig.host : "(ยังไม่ตั้งค่า)"

    private var dataService: SupabaseService?
    private var realtimeTask: Task<Void, Never>?

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
        realtimeTask?.cancel()
        realtimeTask = dataService.subscribeToTransactions { [weak self] in
            Task { await self?.refresh() }
        }
    }

    func loadInitial() async {
        await refresh()
    }

    func refresh() async {
        guard let dataService else { return }
        isLoading = transactions.isEmpty
        var errors: [String] = []

        // Fetch independently so one failing endpoint cannot blank the whole app.
        do {
            let fetchResult = try await dataService.fetchTransactions()
            transactions = fetchResult.transactions
            lastFetchTransactionCount = fetchResult.transactions.count
            lastSkippedTransactionCount = fetchResult.skippedCount
            lastFetchedAt = Date()
        } catch {
            errors.append("transactions: \(error.localizedDescription)")
        }

        do {
            let e = try await dataService.fetchEmployees()
            employees = e
            lastFetchEmployeeCount = e.count
        } catch {
            errors.append("employees: \(error.localizedDescription)")
        }

        do {
            settings = try await dataService.fetchSettings()
        } catch {
            errors.append("settings: \(error.localizedDescription)")
        }

        if transactions.isEmpty && !errors.isEmpty {
            errorMessage = errors.joined(separator: " · ")
        } else if !errors.isEmpty && transactions.isEmpty == false {
            // Soft warning — keep data, surface issue in Profile diagnostics
            errorMessage = errors.joined(separator: " · ")
        } else {
            errorMessage = nil
        }

        isLoading = false
    }

    deinit {
        realtimeTask?.cancel()
    }
}
