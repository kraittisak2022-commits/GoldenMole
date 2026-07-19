import SwiftUI

enum AppMainTab: Hashable {
    case home
    case realtime
    case reports
    case calendar
    case market
}

struct DashboardShell: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var mainTab: AppMainTab = .realtime
    @State private var homeSegment: HomeSegment = .v1
    @State private var showProfile = false

    private enum HomeSegment: String, CaseIterable, Identifiable {
        case v1 = "ภาพรวม V.1"
        case v5 = "ภาพรวม V.5"
        case worklog = "บันทึกงาน"
        var id: String { rawValue }
    }

    init() {
        Self.applyTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $mainTab) {
            NavigationStack {
                homeTab
            }
            .tabItem { Label("หน้าหลัก", systemImage: "square.grid.2x2.fill") }
            .tag(AppMainTab.home)

            NavigationStack {
                realtimeTab
            }
            .tabItem { Label("Real-time", systemImage: "dot.radiowaves.left.and.right") }
            .tag(AppMainTab.realtime)

            NavigationStack {
                reportsHub
            }
            .tabItem { Label("รายงาน", systemImage: "chart.bar.doc.horizontal.fill") }
            .tag(AppMainTab.reports)

            NavigationStack {
                calendarTab
            }
            .tabItem { Label("ปฏิทิน", systemImage: "calendar") }
            .tag(AppMainTab.calendar)

            NavigationStack {
                marketTab
            }
            .tabItem { Label("ทอง/น้ำมัน", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppMainTab.market)
        }
        .tint(AppTheme.brand)
        .task {
            await appState.refresh()
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("เสร็จ") { showProfile = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .environment(auth)
            .environment(appState)
        }
    }

    // MARK: - Home

    private var homeTab: some View {
        let appStateBindable = Bindable(appState)
        return VStack(spacing: 0) {
            DateFilterBar(
                datePreset: appStateBindable.datePreset,
                customStart: appStateBindable.customStart,
                customEnd: appStateBindable.customEnd
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
                        case .worklog:
                            WorkLogView(
                                transactions: appState.transactions,
                                employees: appState.employees,
                                settings: appState.settings
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
        .toolbar { headerToolbar }
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
            .scrollContentBackground(.hidden)
        }
        // The web "Real-time V.4" share view is always a dark, premium dashboard —
        // force a dark page + colorScheme here regardless of the device appearance.
        .background(RealtimeV4Palette.page.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            headerControlsOverlay
        }
    }

    // MARK: - Market (Gold / Oil AI)

    private var marketTab: some View {
        MarketInsightsView(
            insight: appState.marketInsight,
            loading: appState.marketLoading,
            error: appState.marketError,
            onRefresh: { await appState.loadMarket() }
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Reports hub

    private var reportsHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceXL) {
                reportsHero

                reportsSection(title: "วิเคราะห์และรายการ", systemImage: "sparkles") {
                    reportLink(
                        title: "วิเคราะห์ (V.2)",
                        subtitle: "รายจ่ายและแนวโน้ม",
                        icon: "chart.bar.xaxis",
                        color: AppTheme.info,
                        destination: {
                            reportDetail(title: "วิเคราะห์ (V.2)") {
                                AnalyticsV2View(
                                    transactions: appState.filteredTransactions,
                                    settings: appState.settings,
                                    dateFilter: appState.dateFilter
                                )
                            }
                        }
                    )
                    reportLink(
                        title: "รายการบันทึก",
                        subtitle: "ค้นหาธุรกรรมทั้งหมด",
                        icon: "list.bullet.rectangle.portrait",
                        color: AppTheme.slate,
                        destination: {
                            RecordListView(transactions: appState.transactions)
                        }
                    )
                    reportLink(
                        title: "ทอง/น้ำมัน (AI)",
                        subtitle: "วิเคราะห์แนวโน้มราคารายวัน",
                        icon: "chart.line.uptrend.xyaxis",
                        color: AppTheme.warning,
                        destination: {
                            MarketInsightsView(
                                insight: appState.marketInsight,
                                loading: appState.marketLoading,
                                error: appState.marketError,
                                onRefresh: { await appState.loadMarket() }
                            )
                            .navigationTitle("ทอง/น้ำมัน")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    )
                }

                reportsSection(title: "รายงานตามหมวด", systemImage: "square.grid.2x2.fill") {
                    reportLink(
                        title: "ค่าแรง",
                        subtitle: "สรุปค่าแรงตามช่วง",
                        icon: "person.2.fill",
                        color: AppTheme.labor,
                        destination: { categoryDetail(.labor) }
                    )
                    reportLink(
                        title: "การใช้รถ",
                        subtitle: "ค่าใช้จ่ายยานพาหนะ",
                        icon: "truck.box.fill",
                        color: AppTheme.vehicle,
                        destination: { categoryDetail(.vehicle) }
                    )
                    reportLink(
                        title: "ล้างทราย",
                        subtitle: "ทรายและถัง",
                        icon: "drop.fill",
                        color: AppTheme.sand,
                        destination: { categoryDetail(.sand) }
                    )
                    reportLink(
                        title: "น้ำมัน",
                        subtitle: "ดีเซล / เบนซิน",
                        icon: "fuelpump.fill",
                        color: AppTheme.fuel,
                        destination: { categoryDetail(.fuel) }
                    )
                    reportLink(
                        title: "ที่ดิน",
                        subtitle: "โครงการและค่าใช้จ่าย",
                        icon: "map.fill",
                        color: AppTheme.land,
                        destination: { categoryDetail(.land) }
                    )
                    reportLink(
                        title: "รายรับ",
                        subtitle: "สรุปรายได้",
                        icon: "banknote.fill",
                        color: AppTheme.income,
                        destination: { categoryDetail(.income) }
                    )
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("รายงาน")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { headerToolbar }
    }

    private var reportsHero: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text("ศูนย์รายงาน")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("เลือกดูสรุปตามมุมมองหรือหมวดหมู่")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.brand, AppTheme.brandMid],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.25), radius: 12, y: 6)
    }

    private func reportsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            SectionHeader(title: title, systemImage: systemImage)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                content()
            }
        }
    }

    private func reportLink<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .shadow(color: color.opacity(0.35), radius: 6, y: 3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color.opacity(0.6))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .stroke(color.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
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
        let appStateBindable = Bindable(appState)
        return VStack(spacing: 0) {
            DateFilterBar(
                datePreset: appStateBindable.datePreset,
                customStart: appStateBindable.customStart,
                customEnd: appStateBindable.customEnd
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
        .toolbar { headerToolbar }
    }

    // MARK: - Header controls (refresh + appearance + profile)

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            appearanceToggle
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            refreshButton
            avatarButton
        }
    }

    /// Floating cluster for the Real-time tab, which hides its navigation bar.
    private var headerControlsOverlay: some View {
        HStack(spacing: 10) {
            appearanceToggle
            Divider()
                .frame(height: 20)
                .overlay(Color.white.opacity(0.15))
            refreshButton
            avatarButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .padding(.top, 6)
        .padding(.trailing, AppTheme.spaceLG)
    }

    private var refreshButton: some View {
        Button {
            Task { await appState.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(appState.isLoading)
        .accessibilityLabel("รีเฟรชข้อมูล")
    }

    /// Light/dark switch — separate control from the profile avatar.
    private var appearanceToggle: some View {
        Toggle(isOn: isDarkModeBinding) {
            Image(systemName: isDarkModeBinding.wrappedValue ? "moon.stars.fill" : "sun.max.fill")
        }
        .toggleStyle(.switch)
        .labelsHidden()
        .tint(AppTheme.brand)
        .accessibilityLabel("สลับโหมดสว่าง/มืด")
    }

    /// True when the app is showing dark. Writing flips between explicit light/dark.
    private var isDarkModeBinding: Binding<Bool> {
        Binding(
            get: {
                switch currentAppearance {
                case .dark: return true
                case .light: return false
                case .system: return systemScheme == .dark
                }
            },
            set: { newValue in
                appearanceMode = (newValue ? AppearanceMode.dark : AppearanceMode.light).rawValue
            }
        )
    }

    private var avatarButton: some View {
        Button {
            showProfile = true
        } label: {
            AvatarCircle(
                avatar: auth.currentAdmin?.avatar ?? "",
                initials: profileInitials,
                size: 30
            )
        }
        .accessibilityLabel("โปรไฟล์")
    }

    private var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private var profileInitials: String {
        let name = auth.currentAdmin?.displayName ?? auth.currentAdmin?.username ?? "?"
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        if parts.isEmpty { return "?" }
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private static func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.25)

        let brand = UIColor(AppTheme.brand)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.selected.iconColor = brand
            item.selected.titleTextAttributes = [
                .foregroundColor: brand,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
            item.normal.titleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @ViewBuilder
    private func loadingOr<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if appState.isLoading && appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ProgressView("กำลังโหลดข้อมูล…")
                    .tint(AppTheme.brand)
                Text("เชื่อมต่อ \(appState.supabaseHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = appState.errorMessage, appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                EmptyStateView(
                    title: "โหลดไม่สำเร็จ",
                    message: "\(error)\n\nHost: \(appState.supabaseHost)",
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
        } else if appState.hasEmptySuccessfulFetch {
            VStack(spacing: 12) {
                Spacer()
                EmptyStateView(
                    title: "เชื่อมต่อสำเร็จ แต่ยังไม่มีข้อมูล",
                    message: "ดึงจาก \(appState.supabaseHost) ได้ 0 รายการ\nถ้าเว็บมีข้อมูล ให้ตรวจว่า SUPABASE_URL ใน Codemagic ตรงกับเว็บ (ดูแท็บโปรไฟล์)",
                    systemImage: "tray"
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
