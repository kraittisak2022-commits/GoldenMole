import SwiftUI

/// Wraps a category report with its own day/range control.
///
/// Reports start on today. The scope lives here rather than in `AppState` so switching days
/// in a report leaves the Home tab's filter alone.
struct CategoryReportScreen: View {
    let type: CategoryReportType
    var titleOverride: String? = nil

    @Environment(AppState.self) private var appState
    @State private var scope = ReportDateScope()

    private var scoped: [Transaction] {
        DashboardAggregations.filterByRange(appState.transactions, range: scope.filter)
    }

    private var hasData: Bool {
        if scoped.contains(where: { type.matches($0) }) { return true }
        guard type == .fuel else { return false }
        return !FuelUsageReportLogic.buildReport(
            transactions: scoped,
            start: scope.filter.start,
            end: scope.filter.end,
            allTransactionsForEstimate: appState.transactions
        ).rows.isEmpty
    }

    /// Newest day inside the fetch window that actually has rows for this category.
    private var latestDayWithData: String? {
        appState.transactions
            .filter { type.matches($0) }
            .map { String($0.date.prefix(10)) }
            .max()
    }

    var body: some View {
        VStack(spacing: 0) {
            ReportDateBar(
                scope: $scope,
                fuelCalendarTransactions: type == .fuel ? appState.transactions : nil,
                fuelCalendarRevision: type == .fuel ? appState.transactionsRevision : 0
            )
                .padding(.horizontal, AppTheme.spaceLG)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceSoft.opacity(0.85))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppTheme.hairline)
                        .frame(height: 1)
                }

            ScrollView {
                Group {
                    if hasData {
                        CategoryReportView(
                            type: type,
                            transactions: scoped,
                            settings: appState.settings,
                            employees: appState.employees,
                            dateFilter: scope.filter,
                            scopeTitle: scope.title,
                            stockTransactions: appState.transactions
                        )
                    } else {
                        emptyCard
                    }
                }
                .padding(AppTheme.spaceLG)
            }
            .refreshable { await appState.refresh(forceFull: true) }
            .scrollContentBackground(.hidden)
        }
        .background(DashboardBackground())
        .navigationTitle(titleOverride ?? type.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty

    private var emptyCard: some View {
        SectionCard {
            EmptyStateView(
                title: "ไม่มีข้อมูล\(type.title)\(scope.isSingleDay ? "ใน\(scope.title)" : "ในช่วงนี้")",
                message: emptyMessage,
                systemImage: "tray"
            )

            if let latest = latestDayWithData {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        scope.selectDayKey(latest)
                    }
                } label: {
                    Label(
                        "ไปวันที่ \(DashboardAggregations.thaiDateLong(latest))",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
            }

            if scope.isSingleDay {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        scope.useRange(.days7)
                    }
                } label: {
                    Label("ดู 7 วันล่าสุด", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.brand)
            }
        }
    }

    private var emptyMessage: String {
        if latestDayWithData == nil {
            return "ยังไม่เคยมีการบันทึกหมวดนี้ในช่วง \(ReportDateScope.historyWindowDays) วันล่าสุด"
        }
        return "ลองเลื่อนวันหรือเปลี่ยนไปดูแบบช่วง"
    }
}
