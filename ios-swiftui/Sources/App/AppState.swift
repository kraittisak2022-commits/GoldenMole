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

    private var dataService: SupabaseService?
    private var realtimeTask: Task<Void, Never>?

    var dateFilter: DateFilter {
        DashboardAggregations.dateFilter(preset: datePreset, customStart: customStart, customEnd: customEnd)
    }

    var filteredTransactions: [Transaction] {
        DashboardAggregations.filterByRange(transactions, range: dateFilter)
    }

    func configure(dataService: SupabaseService) {
        self.dataService = dataService
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
        errorMessage = nil
        do {
            async let txs = dataService.fetchTransactions()
            async let emps = dataService.fetchEmployees()
            async let sett = dataService.fetchSettings()
            let (t, e, s) = try await (txs, emps, sett)
            transactions = t
            employees = e
            settings = s
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    deinit {
        realtimeTask?.cancel()
    }
}
