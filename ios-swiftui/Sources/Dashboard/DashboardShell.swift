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
    @State private var homeSegment: HomeSegment = .overview
    @State private var showProfile = false

    private enum HomeSegment: String, CaseIterable, Identifiable {
        case overview = "เธ เธฒเธเธฃเธงเธก"
        case worklog = "เธเธฑเธเธ—เธถเธเธเธฒเธ"
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
            .tabItem { Label("เธซเธเนเธฒเธซเธฅเธฑเธ", systemImage: "square.grid.2x2.fill") }
            .tag(AppMainTab.home)

            NavigationStack {
                realtimeTab
            }
            .tabItem { Label("Real-time", systemImage: "dot.radiowaves.left.and.right") }
            .tag(AppMainTab.realtime)

            NavigationStack {
                reportsHub
            }
            .tabItem { Label("เธฃเธฒเธขเธเธฒเธ", systemImage: "chart.bar.doc.horizontal.fill") }
            .tag(AppMainTab.reports)

            NavigationStack {
                calendarTab
            }
            .tabItem { Label("เธเธเธดเธ—เธดเธ", systemImage: "calendar") }
            .tag(AppMainTab.calendar)

            NavigationStack {
                marketTab
            }
            .tabItem { Label("เธ—เธญเธ/เธเนเธณเธกเธฑเธ", systemImage: "chart.line.uptrend.xyaxis") }
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
                            Button("เน€เธชเธฃเนเธ") { showProfile = false }
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
            Picker("เธกเธธเธกเธกเธญเธ", selection: $homeSegment) {
                ForEach(HomeSegment.allCases) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.vertical, 10)

            loadingOr {
                switch homeSegment {
                case .overview:
                    OverviewHubView(
                        transactions: appState.filteredTransactions,
                        allTransactions: appState.transactions,
                        settings: appState.settings,
                        dateFilter: appState.dateFilter
                    )
                    .refreshable { await appState.refresh() }
                case .worklog:
                    ScrollView {
                        WorkLogView(
                            transactions: appState.transactions,
                            employees: appState.employees,
                            settings: appState.settings
                        )
                        .padding(AppTheme.spaceLG)
                    }
                    .refreshable { await appState.refresh() }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(DashboardBackground())
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
        .background(RealtimeV4Palette.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
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

                reportsSection(title: "เธงเธดเน€เธเธฃเธฒเธฐเธซเนเนเธฅเธฐเธฃเธฒเธขเธเธฒเธฃ", systemImage: "sparkles") {
                    reportLink(
                        title: "เธฃเธฒเธขเธเธฒเธฃเธเธฑเธเธ—เธถเธ",
                        subtitle: "เธเนเธเธซเธฒเธเธธเธฃเธเธฃเธฃเธกเธ—เธฑเนเธเธซเธกเธ”",
                        icon: "list.bullet.rectangle.portrait",
                        color: AppTheme.slate,
                        destination: {
                            RecordListView(transactions: appState.transactions)
                        }
                    )
                    reportLink(
                        title: "เธ—เธญเธ/เธเนเธณเธกเธฑเธ (AI)",
                        subtitle: "เธงเธดเน€เธเธฃเธฒเธฐเธซเนเนเธเธงเนเธเนเธกเธฃเธฒเธเธฒเธฃเธฒเธขเธงเธฑเธ",
                        icon: "chart.line.uptrend.xyaxis",
                        color: AppTheme.warning,
                        destination: {
                            MarketInsightsView(
                                insight: appState.marketInsight,
                                loading: appState.marketLoading,
                                error: appState.marketError,
                                onRefresh: { await appState.loadMarket() }
                            )
                            .navigationTitle("เธ—เธญเธ/เธเนเธณเธกเธฑเธ")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    )
                }

                reportsSection(title: "เธฃเธฒเธขเธเธฒเธเธ•เธฒเธกเธซเธกเธงเธ”", systemImage: "square.grid.2x2.fill") {
                    reportLink(
                        title: "เธเนเธฒเนเธฃเธ",
                        subtitle: "เธชเธฃเธธเธเธเนเธฒเนเธฃเธเธ•เธฒเธกเธเนเธงเธ",
                        icon: "person.2.fill",
                        color: AppTheme.labor,
                        destination: { categoryDetail(.labor) }
                    )
                    reportLink(
                        title: "เธเธฒเธฃเนเธเนเธฃเธ–",
                        subtitle: "เธเนเธฒเนเธเนเธเนเธฒเธขเธขเธฒเธเธเธฒเธซเธเธฐ",
                        icon: "truck.box.fill",
                        color: AppTheme.vehicle,
                        destination: { categoryDetail(.vehicle) }
                    )
                    reportLink(
                        title: "เธฅเนเธฒเธเธ—เธฃเธฒเธข",
                        subtitle: "เธ—เธฃเธฒเธขเนเธฅเธฐเธ–เธฑเธ",
                        icon: "drop.fill",
                        color: AppTheme.sand,
                        destination: { categoryDetail(.sand) }
                    )
                    reportLink(
                        title: "เธเนเธณเธกเธฑเธ",
                        subtitle: "เธ”เธตเน€เธเธฅ / เน€เธเธเธเธดเธ",
                        icon: "fuelpump.fill",
                        color: AppTheme.fuel,
                        destination: { categoryDetail(.fuel) }
                    )
                    reportLink(
                        title: "เธ—เธตเนเธ”เธดเธ",
                        subtitle: "เนเธเธฃเธเธเธฒเธฃเนเธฅเธฐเธเนเธฒเนเธเนเธเนเธฒเธข",
                        icon: "map.fill",
                        color: AppTheme.land,
                        destination: { categoryDetail(.land) }
                    )
                    reportLink(
                        title: "เธฃเธฒเธขเธฃเธฑเธ",
                        subtitle: "เธชเธฃเธธเธเธฃเธฒเธขเนเธ”เน",
                        icon: "banknote.fill",
                        color: AppTheme.income,
                        destination: { categoryDetail(.income) }
                    )
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .background(DashboardBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("เธฃเธฒเธขเธเธฒเธ")
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
                Text("เธจเธนเธเธขเนเธฃเธฒเธขเธเธฒเธ")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("เน€เธฅเธทเธญเธเธ”เธนเธชเธฃเธธเธเธ•เธฒเธกเธกเธธเธกเธกเธญเธเธซเธฃเธทเธญเธซเธกเธงเธ”เธซเธกเธนเน")
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
        .shadow(color: AppTheme.brand.opacity(0.35), radius: 14, y: 6)
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
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .fill(AppTheme.surface)
                    .shadow(color: AppTheme.cardShadow, radius: 14, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 1)
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
            .scrollContentBackground(.hidden)
        }
        .background(DashboardBackground())
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
            .scrollContentBackground(.hidden)
        }
        .background(DashboardBackground())
        .navigationTitle("เธเธเธดเธ—เธดเธ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { headerToolbar }
    }

    // MARK: - Header controls (profile + appearance)

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            avatarButton
            appearanceButton
        }
    }

    /// Floating cluster for the Real-time tab, which hides its navigation bar.
    private var headerControlsOverlay: some View {
        HStack(spacing: 10) {
            avatarButton
            Divider()
                .frame(height: 20)
                .overlay(Color.primary.opacity(0.15))
            appearanceButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .padding(.top, 6)
        .padding(.leading, AppTheme.spaceLG)
    }

    /// Pro sun/moon icon button โ€” tap to flip light/dark.
    private var appearanceButton: some View {
        let isDark = isDarkModeBinding.wrappedValue
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                isDarkModeBinding.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: isDark ? "moon.stars.fill" : "sun.max.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDark ? Color(hex: "#C7D2FE") : Color(hex: "#F59E0B"))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เธชเธฅเธฑเธเนเธซเธกเธ”เธชเธงเนเธฒเธ/เธกเธทเธ”")
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
        .accessibilityLabel("เนเธเธฃเนเธเธฅเน")
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
                ProgressView("เธเธณเธฅเธฑเธเนเธซเธฅเธ”เธเนเธญเธกเธนเธฅโ€ฆ")
                    .tint(AppTheme.brand)
                Text("เน€เธเธทเนเธญเธกเธ•เนเธญ \(appState.supabaseHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = appState.errorMessage, appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                EmptyStateView(
                    title: "เนเธซเธฅเธ”เนเธกเนเธชเธณเน€เธฃเนเธ",
                    message: "\(error)\n\nHost: \(appState.supabaseHost)",
                    systemImage: "wifi.exclamationmark"
                )
                Button("เธฅเธญเธเธญเธตเธเธเธฃเธฑเนเธ") {
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
                    title: "เน€เธเธทเนเธญเธกเธ•เนเธญเธชเธณเน€เธฃเนเธ เนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเนเธญเธกเธนเธฅ",
                    message: "เธ”เธถเธเธเธฒเธ \(appState.supabaseHost) เนเธ”เน 0 เธฃเธฒเธขเธเธฒเธฃ\nเธ–เนเธฒเน€เธงเนเธเธกเธตเธเนเธญเธกเธนเธฅ เนเธซเนเธ•เธฃเธงเธเธงเนเธฒ SUPABASE_URL เนเธ Codemagic เธ•เธฃเธเธเธฑเธเน€เธงเนเธ (เธ”เธนเนเธ—เนเธเนเธเธฃเนเธเธฅเน)",
                    systemImage: "tray"
                )
                Button("เธฅเธญเธเธญเธตเธเธเธฃเธฑเนเธ") {
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
