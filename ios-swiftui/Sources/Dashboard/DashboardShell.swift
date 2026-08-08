import SwiftUI

enum AppMainTab: Hashable {
    case home
    case realtimeTrip
    case realtimeSand
    case tasks
    case calendar
}

private enum HomeSegment: String, CaseIterable, Identifiable {
    case overview = "ภาพรวม"
    case worklog = "บันทึกงาน"
    case reports = "รายงาน"
    var id: String { rawValue }
}

struct DashboardShell: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppState.self) private var appState
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var mainTab: AppMainTab = .realtimeTrip
    @State private var homeSegment: HomeSegment = .overview
    @State private var showProfile = false

    private var isRealtimeTabActive: Bool {
        mainTab == .realtimeTrip || mainTab == .realtimeSand
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
                realtimeBoard(mode: .sand)
            }
            .tabItem { Label("ร่อนทราย", systemImage: "drop.fill") }
            .tag(AppMainTab.realtimeSand)

            NavigationStack {
                realtimeBoard(mode: .trip)
            }
            .tabItem { Label("เที่ยวรถ", systemImage: "truck.box.fill") }
            .tag(AppMainTab.realtimeTrip)

            NavigationStack {
                tasksTab
            }
            .tabItem { Label("งาน", systemImage: "checklist") }
            .badge(taskStore.inboxCount)
            .tag(AppMainTab.tasks)

            NavigationStack {
                calendarTab
            }
            .tabItem { Label("ปฏิทิน", systemImage: "calendar") }
            .tag(AppMainTab.calendar)
        }
        .tint(AppTheme.brand)
        .task {
            await appState.refresh()
        }
        .task(id: auth.currentAdmin?.id) {
            // Load tasks before the "งาน" tab is ever opened so the assignment badge is accurate.
            taskStore.currentAdminId = auth.currentAdmin?.id ?? ""
            await taskStore.loadIfNeeded()
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
            homeControlRow()

            if appState.datePreset == .custom {
                HStack {
                    DatePicker("เริ่ม", selection: appStateBindable.customStart, displayedComponents: .date)
                        .labelsHidden()
                    Text("–")
                        .foregroundStyle(AppTheme.inkMuted)
                    DatePicker("สิ้นสุด", selection: appStateBindable.customEnd, displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .padding(.horizontal, AppTheme.spaceLG)
                .padding(.bottom, 8)
            }

            loadingOr {
                switch homeSegment {
                case .overview:
                    OverviewHubView(
                        transactions: appState.filteredTransactions,
                        allTransactions: appState.transactions,
                        employees: appState.employees,
                        settings: appState.settings,
                        dateFilter: appState.dateFilter,
                        greetingName: auth.currentAdmin?.displayName
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
                case .reports:
                    reportsHub
                        .refreshable { await appState.refresh() }
                }
            }
        }
        .background(DashboardBackground())
        .navigationTitle(appState.settings.appName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { headerToolbar }
    }

    /// Compact pill segment + date-range chip for the Home tab.
    private func homeControlRow() -> some View {
        HStack(spacing: 10) {
            HomeSegmentPill(selection: $homeSegment)
            Spacer(minLength: 0)
            Menu {
                ForEach(DateRangePreset.allCases) { preset in
                    Button {
                        appState.datePreset = preset
                    } label: {
                        if appState.datePreset == preset {
                            Label(preset.label, systemImage: "checkmark")
                        } else {
                            Text(preset.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(appState.datePreset.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppTheme.surfaceSoft)
                )
                .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.vertical, 10)
    }

    // MARK: - Realtime

    private func realtimeBoard(mode: RealtimeBoardMode) -> some View {
        loadingOr {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    RealtimeV4View(
                        transactions: appState.transactions,
                        employees: appState.employees,
                        settings: appState.settings,
                        transactionsRevision: appState.transactionsRevision,
                        mode: mode,
                        isRealtimeTabActive: isRealtimeTabActive
                    )
                }
                .padding(AppTheme.spaceLG)
            }
            .refreshable { await appState.refresh() }
            .scrollContentBackground(.hidden)
        }
        .background(RealtimeV4Palette.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            headerControlsOverlay
        }
    }

    // MARK: - Tasks

    private var tasksTab: some View {
        TasksHubView()
            .toolbar { headerToolbar }
    }

    // MARK: - Reports hub

    private var reportsHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceXL) {
                MobileDailyAuditCard(
                    transactions: appState.transactions,
                    employees: appState.employees
                )

                reportsHero

                reportsSection(
                    eyebrow: "INSIGHTS",
                    title: "วิเคราะห์และรายการ",
                    subtitle: "มุมมองรวมและรายการธุรกรรม"
                ) {
                    reportLink(
                        title: "รายการบันทึก",
                        subtitle: "ค้นหาธุรกรรมทั้งหมด",
                        icon: "list.bullet.rectangle.portrait",
                        color: AppTheme.slate,
                        showsDivider: false,
                        destination: {
                            RecordListView(transactions: appState.transactions)
                        }
                    )
                }

                reportsSection(
                    eyebrow: "CATEGORIES",
                    title: "รายงานตามหมวด",
                    subtitle: "สรุปวันนี้ · แตะการ์ดเพื่อดูรายละเอียด"
                ) {
                    categorySummaryGrid
                }
            }
            .padding(AppTheme.spaceLG)
            .padding(.bottom, AppTheme.spaceXL)
        }
        .scrollContentBackground(.hidden)
    }

    private var todayKey: String { DashboardAggregations.todayYMD() }

    private var categorySummaryGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CategoryReportType.allCases) { type in
                let summary = type.hubSummary(
                    dayKey: todayKey,
                    transactions: appState.transactions,
                    employees: appState.employees,
                    settings: appState.settings
                )
                NavigationLink {
                    categoryDetail(type)
                } label: {
                    categorySummaryCard(type: type, summary: summary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func categorySummaryCard(type: CategoryReportType, summary: CategoryHubSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: type.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(type.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(type.accent.opacity(0.14))
                    )
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.inkMuted.opacity(0.7))
                    .padding(.top, 4)
            }

            Text(type.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkSecondary)

            Text(summary.primary)
                .font(.title3.weight(.bold))
                .foregroundStyle(summary.hasData ? AppTheme.ink : AppTheme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text(summary.secondary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surfaceSoft.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    summary.hasData ? type.accent.opacity(0.28) : AppTheme.hairline,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.title) \(summary.primary) \(summary.secondary)")
    }

    private var reportsHero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 150, height: 150)
                .blur(radius: 26)
                .offset(x: 210, y: -48)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REPORTS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("ศูนย์รายงาน")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("เลือกดูสรุปตามมุมมองหรือหมวดหมู่")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                        .accessibilityHidden(true)
                }

                HStack(spacing: 10) {
                    reportsHeroChip(title: "มุมมอง", value: "1", tint: Color(hex: "#A7F3D0"))
                    reportsHeroChip(title: "หมวด", value: "\(CategoryReportType.allCases.count)", tint: Color(hex: "#CFFAFE"))
                    reportsHeroChip(
                        title: "วันนี้",
                        value: categoryHubExpenseTodayLabel,
                        tint: Color(hex: "#FDE68A")
                    )
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ศูนย์รายงาน เลือกดูสรุปตามมุมมองหรือหมวดหมู่")
    }

    private var categoryHubExpenseTodayLabel: String {
        let day = todayKey
        let types: [CategoryReportType] = [.labor, .vehicle, .fuel, .land]
        let total = types.reduce(0.0) { sum, type in
            let dayTx = appState.transactions.filter {
                String($0.date.prefix(10)) == day && type.matches($0)
            }
            switch type {
            case .labor, .vehicle:
                return sum + dayTx.reduce(0.0) {
                    $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: appState.employees)
                }
            case .fuel, .land:
                return sum + dayTx.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
            default:
                return sum
            }
        }
        if total <= 0 { return "—" }
        if total >= 1000 {
            return "฿\(DashboardAggregations.formatNumber(total / 1000))k"
        }
        return DashboardAggregations.formatCurrency(total)
    }

    private func reportsHeroChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private func reportsSection<Content: View>(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.brand)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .fill(AppTheme.surface)
                    .shadow(color: AppTheme.cardShadow, radius: 16, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous))
        }
    }

    private func reportLink<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        showsDivider: Bool = true,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(color.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(color.opacity(0.22), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(AppTheme.hairline)
                    .frame(height: 1)
                    .padding(.leading, 70)
            }
        }
    }

    private func categoryDetail(_ type: CategoryReportType) -> some View {
        CategoryReportScreen(type: type)
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
        .navigationTitle("ปฏิทิน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { headerToolbar }
    }

    // MARK: - Header controls (profile + appearance)

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            appearanceButton
            avatarButton
        }
    }

    /// Floating cluster for the Real-time tab, which hides its navigation bar.
    private var headerControlsOverlay: some View {
        HStack(spacing: 10) {
            appearanceButton
            Divider()
                .frame(height: 20)
                .overlay(Color.primary.opacity(0.15))
            avatarButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .padding(.top, 6)
        .padding(.trailing, AppTheme.spaceLG)
    }

    /// Pro sun/moon icon button — tap to flip light/dark.
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


// MARK: - Home segment pill

private struct HomeSegmentPill: View {
    @Binding var selection: HomeSegment
    @Namespace private var pillNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeSegment.allCases) { seg in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = seg }
                } label: {
                    Text(seg.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selection == seg ? .white : AppTheme.inkMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background {
                            if selection == seg {
                                Capsule()
                                    .fill(AppTheme.brand)
                                    .matchedGeometryEffect(id: "homeSegThumb", in: pillNS)
                                    .shadow(color: AppTheme.brand.opacity(0.35), radius: 6, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(AppTheme.surfaceSoft))
        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
    }
}
