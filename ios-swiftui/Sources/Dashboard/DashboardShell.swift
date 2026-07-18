import SwiftUI

enum AppMainTab: Hashable {
    case home
    case realtime
    case reports
    case calendar
    case profile
}

struct DashboardShell: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState
    @State private var mainTab: AppMainTab = .realtime
    @State private var homeSegment: HomeSegment = .v1

    private enum HomeSegment: String, CaseIterable, Identifiable {
        case v1 = "ภาพรวม V.1"
        case v5 = "ภาพรวม V.5"
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $mainTab) {
            NavigationStack {
                homeTab
            }
            .tabItem { Label("หน้าหลัก", systemImage: "chart.pie.fill") }
            .tag(AppMainTab.home)

            NavigationStack {
                realtimeTab
            }
            .tabItem { Label("Real-time", systemImage: "dot.radiowaves.left.and.right") }
            .tag(AppMainTab.realtime)

            NavigationStack {
                reportsHub
            }
            .tabItem { Label("รายงาน", systemImage: "list.bullet.rectangle") }
            .tag(AppMainTab.reports)

            NavigationStack {
                calendarTab
            }
            .tabItem { Label("ปฏิทิน", systemImage: "calendar") }
            .tag(AppMainTab.calendar)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("โปรไฟล์", systemImage: "person.crop.circle") }
            .tag(AppMainTab.profile)
        }
        .tint(AppTheme.brand)
    }

    // MARK: - Home

    private var homeTab: some View {
        VStack(spacing: 0) {
            DateFilterBar(
                datePreset: $appState.datePreset,
                customStart: $appState.customStart,
                customEnd: $appState.customEnd
            )
            Picker("มุมมอง", selection: $homeSegment) {
                ForEach(HomeSegment.allCases) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.vertical, 10)

            loadingOr {
                ScrollView {
                    Group {
                        switch homeSegment {
                        case .v1:
                            OverviewV1View(
                                transactions: appState.filteredTransactions,
                                dateFilter: appState.dateFilter
                            )
                        case .v5:
                            CompareV5View(
                                transactions: appState.transactions,
                                dateFilter: appState.dateFilter
                            )
                        }
                    }
                    .padding(AppTheme.spaceLG)
                }
                .refreshable { await appState.refresh() }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(appState.settings.appName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { refreshToolbar }
    }

    // MARK: - Realtime

    private var realtimeTab: some View {
        loadingOr {
            ScrollView {
                RealtimeV4View(
                    transactions: appState.transactions,
                    employees: appState.employees,
                    settings: appState.settings
                )
                .padding(AppTheme.spaceLG)
            }
            .refreshable { await appState.refresh() }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Real-time V.4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { refreshToolbar }
    }

    // MARK: - Reports hub

    private var reportsHub: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                reportLink(
                    title: "วิเคราะห์ (V.2)",
                    subtitle: "รายจ่ายและแนวโน้ม",
                    icon: "chart.bar.xaxis",
                    color: AppTheme.info,
                    destination: AnyView(
                        reportDetail(title: "วิเคราะห์ (V.2)") {
                            AnalyticsV2View(
                                transactions: appState.filteredTransactions,
                                settings: appState.settings,
                                dateFilter: appState.dateFilter
                            )
                        }
                    )
                )
                reportLink(
                    title: "ค่าแรง",
                    subtitle: "สรุปค่าแรงตามช่วง",
                    icon: "person.2.fill",
                    color: AppTheme.labor,
                    destination: AnyView(categoryDetail(.labor))
                )
                reportLink(
                    title: "การใช้รถ",
                    subtitle: "ค่าใช้จ่ายยานพาหนะ",
                    icon: "truck.box.fill",
                    color: AppTheme.vehicle,
                    destination: AnyView(categoryDetail(.vehicle))
                )
                reportLink(
                    title: "ล้างทราย",
                    subtitle: "ทรายและถัง",
                    icon: "drop.fill",
                    color: AppTheme.sand,
                    destination: AnyView(categoryDetail(.sand))
                )
                reportLink(
                    title: "น้ำมัน",
                    subtitle: "ดีเซล / เบนซิน",
                    icon: "fuelpump.fill",
                    color: AppTheme.fuel,
                    destination: AnyView(categoryDetail(.fuel))
                )
                reportLink(
                    title: "ที่ดิน",
                    subtitle: "โครงการและค่าใช้จ่าย",
                    icon: "map.fill",
                    color: AppTheme.land,
                    destination: AnyView(categoryDetail(.land))
                )
                reportLink(
                    title: "รายรับ",
                    subtitle: "สรุปรายได้",
                    icon: "banknote.fill",
                    color: AppTheme.income,
                    destination: AnyView(categoryDetail(.income))
                )
                reportLink(
                    title: "รายการบันทึก",
                    subtitle: "ค้นหาธุรกรรมทั้งหมด",
                    icon: "list.bullet.rectangle.portrait",
                    color: AppTheme.slate,
                    destination: AnyView(
                        RecordListView(transactions: appState.transactions)
                    )
                )
            }
            .padding(AppTheme.spaceLG)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("รายงาน")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { refreshToolbar }
    }

    private func reportLink(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryDetail(_ type: CategoryReportType) -> some View {
        reportDetail(title: type.title) {
            CategoryReportView(
                type: type,
                transactions: appState.filteredTransactions,
                settings: appState.settings,
                employees: appState.employees,
                dateFilter: appState.dateFilter
            )
        }
    }

    private func reportDetail<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            DateFilterBar(
                datePreset: $appState.datePreset,
                customStart: $appState.customStart,
                customEnd: $appState.customEnd
            )
            ScrollView {
                content()
                    .padding(AppTheme.spaceLG)
            }
            .refreshable { await appState.refresh() }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Calendar

    private var calendarTab: some View {
        loadingOr {
            ScrollView {
                CalendarV3View(
                    transactions: appState.transactions,
                    employees: appState.employees
                )
                .padding(AppTheme.spaceLG)
            }
            .refreshable { await appState.refresh() }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ปฏิทิน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { refreshToolbar }
    }

    // MARK: - Shared

    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(appState.isLoading)
        }
    }

    @ViewBuilder
    private func loadingOr<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if appState.isLoading && appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ProgressView("กำลังโหลดข้อมูล…")
                    .tint(AppTheme.brand)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = appState.errorMessage, appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                EmptyStateView(
                    title: "โหลดไม่สำเร็จ",
                    message: error,
                    systemImage: "wifi.exclamationmark"
                )
                Button("ลองอีกครั้ง") {
                    Task { await appState.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
                Spacer()
            }
            .padding()
        } else {
            content()
        }
    }
}
