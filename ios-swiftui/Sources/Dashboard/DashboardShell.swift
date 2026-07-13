import SwiftUI

struct DashboardShell: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dashboardHeader
                Divider()
                content
            }
            .navigationTitle(appState.settings.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            auth.logout()
                        } label: {
                            Label("ออกจากระบบ", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                }
            }
        }
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("เลือกหน้าแดชบอร์ด", selection: $appState.selectedTab) {
                Section("มุมมองแนะนำ") {
                    ForEach(DashboardTab.mainTabs) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                Section("มุมมองขั้นสูง") {
                    ForEach(DashboardTab.advancedTabs) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                Section("รายงานตามหมวด") {
                    ForEach(DashboardTab.categoryTabs) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
            }
            .pickerStyle(.menu)

            HStack {
                Picker("ช่วงวันที่", selection: $appState.datePreset) {
                    ForEach(DateRangePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                if appState.datePreset == .custom {
                    DatePicker("เริ่ม", selection: $appState.customStart, displayedComponents: .date)
                        .labelsHidden()
                    Text("–")
                    DatePicker("สิ้นสุด", selection: $appState.customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .font(.subheadline)

            if let admin = auth.currentAdmin {
                Text("ผู้ใช้: \(admin.displayName) (\(admin.role.rawValue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoading && appState.transactions.isEmpty {
            Spacer()
            ProgressView("กำลังโหลดข้อมูล…")
            Spacer()
        } else if let error = appState.errorMessage, appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("โหลดไม่สำเร็จ")
                    .font(.title2.weight(.semibold))
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    switch appState.selectedTab {
                    case .overviewV1:
                        OverviewV1View(transactions: appState.filteredTransactions, dateFilter: appState.dateFilter)
                    case .overviewV5:
                        CompareV5View(transactions: appState.transactions, dateFilter: appState.dateFilter)
                    case .analytics:
                        AnalyticsV2View(transactions: appState.filteredTransactions, settings: appState.settings, dateFilter: appState.dateFilter)
                    case .calendar:
                        CalendarV3View(transactions: appState.transactions, employees: appState.employees)
                    case .realtimeV4:
                        RealtimeV4View(transactions: appState.transactions, employees: appState.employees, settings: appState.settings)
                    case .labor:
                        CategoryReportView(type: .labor, transactions: appState.filteredTransactions, settings: appState.settings, employees: appState.employees, dateFilter: appState.dateFilter)
                    case .vehicle:
                        CategoryReportView(type: .vehicle, transactions: appState.filteredTransactions, settings: appState.settings, employees: appState.employees, dateFilter: appState.dateFilter)
                    case .sand:
                        CategoryReportView(type: .sand, transactions: appState.filteredTransactions, settings: appState.settings, employees: appState.employees, dateFilter: appState.dateFilter)
                    case .fuel:
                        CategoryReportView(type: .fuel, transactions: appState.filteredTransactions, settings: appState.settings, employees: appState.employees, dateFilter: appState.dateFilter)
                    case .land:
                        CategoryReportView(type: .land, transactions: appState.filteredTransactions, settings: appState.settings, employees: appState.employees, dateFilter: appState.dateFilter)
                    case .income:
                        CategoryReportView(type: .income, transactions: appState.filteredTransactions, settings: appState.settings, employees: appState.employees, dateFilter: appState.dateFilter)
                    }
                }
                .padding()
            }
            .refreshable { await appState.refresh() }
        }
    }
}
