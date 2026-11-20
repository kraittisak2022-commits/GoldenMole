import SwiftUI

enum AppMainTab: Hashable {
    case home
    case realtimeTrip
    case realtimeSand
    case albums
    case tasks
}

private enum HomeSegment: String, CaseIterable, Identifiable {
    case overview = "ภาพรวม"
    case worklog = "บันทึกงาน"
    case reports = "รายงาน"
    case calendar = "ปฏิทิน"
    var id: String { rawValue }
}

struct DashboardShell: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppState.self) private var appState
    @Environment(TaskStore.self) private var taskStore
    @Environment(FeedStore.self) private var feedStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var homeDateNS
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var mainTab: AppMainTab = .realtimeTrip
    @State private var homeSegment: HomeSegment = .overview
    @State private var showProfile = false
    @State private var showOpsMenu = false
    @State private var opsMenuDrag: CGFloat = 0
    @State private var opsDestination: OpsMenuItem?
    @State private var showHomeCustomDatePicker = false
    @State private var homeCustomDraft = Date()
    @State private var manualSyncHaptic = 0
    @State private var isManualSyncing = false
    /// Shared focus day for ร่อนทราย + เที่ยวรถ tabs.
    @State private var realtimeFocusDate = Date()
    @State private var updateOffer: AppUpdateChecker.Offer?

    private static let syncTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var isRealtimeTabActive: Bool {
        mainTab == .realtimeTrip || mainTab == .realtimeSand
    }

    private func isRealtimeBoardActive(_ mode: RealtimeBoardMode) -> Bool {
        switch mode {
        case .trip: return mainTab == .realtimeTrip
        case .sand: return mainTab == .realtimeSand
        }
    }

    init() {
        Self.applyTabBarAppearance()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
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
                    PhotoAlbumsView()
                }
                .tabItem { Label("อัลบั้ม", systemImage: "photo.on.rectangle.angled") }
                .tag(AppMainTab.albums)

                NavigationStack {
                    tasksTab
                }
                .tabItem { Label("อัพเดตงาน", systemImage: "newspaper.fill") }
                .badge(feedBadge)
                .tag(AppMainTab.tasks)
            }
            .tint(AppTheme.brand)

            // Invisible right-edge strip — swipe left to open the ops menu.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Color.clear
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(opsEdgeOpenGesture)
                    .accessibilityLabel("เปิดเมนูงานประจำวัน")
                    .accessibilityHint("ปัดซ้ายจากขอบขวาเพื่อเปิดเมนู")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        openOpsMenu()
                    }
            }
            .allowsHitTesting(!showOpsMenu)
            .zIndex(10)

            if showOpsMenu || opsMenuDrag > 0 {
                OpsSideMenuOverlay(
                    isPresented: $showOpsMenu,
                    dragOffset: $opsMenuDrag,
                    onSelect: handleOpsMenuSelect
                )
                .transition(.opacity)
                .zIndex(20)
            }

            if let offer = updateOffer {
                AppUpdatePromptView(
                    offer: offer,
                    onLater: {
                        AppUpdateChecker.snooze(offer)
                        withAnimation(.easeOut(duration: 0.2)) { updateOffer = nil }
                    },
                    onUpdate: {
                        AppUpdateChecker.open(offer)
                        AppUpdateChecker.snooze(offer)
                        withAnimation(.easeOut(duration: 0.2)) { updateOffer = nil }
                    }
                )
                .zIndex(40)
                .transition(.opacity)
            }
        }
        .task {
            await appState.refresh()
            await checkForAppUpdate(force: false)
        }
        .task(id: auth.currentAdmin?.id) {
            // Load tasks before the "งาน" tab is ever opened so the assignment badge is accurate.
            taskStore.currentAdminId = auth.currentAdmin?.id ?? ""
            await taskStore.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await appState.refreshOnForeground()
                await checkForAppUpdate(force: false)
            }
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
        .sheet(item: $opsDestination) { item in
            NavigationStack {
                OpsMenuDestinationView(item: item)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("ปิด") { opsDestination = nil }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .environment(appState)
            .environment(auth)
        }
    }

    private var opsEdgeOpenGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                // Swipe left from the right edge.
                let shouldOpen = value.translation.width < -48
                    || value.predictedEndTranslation.width < -90
                if shouldOpen {
                    openOpsMenu()
                }
            }
    }

    private func openOpsMenu() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showOpsMenu = true
            opsMenuDrag = 0
        }
    }

    @MainActor
    private func checkForAppUpdate(force: Bool) async {
        // Soft delay so login / first paint settle before the prompt.
        if !force {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        }
        let remote = appState.settings.updateRemoteHint
        let offer = await AppUpdateChecker.check(remote: remote, force: force)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            updateOffer = offer
        }
    }

    private func handleOpsMenuSelect(_ item: OpsMenuItem) {
        if let tab = item.switchesToTab {
            mainTab = tab
            return
        }
        opsDestination = item
    }

    // MARK: - Home

    private var homeTab: some View {
        VStack(spacing: 0) {
            homeControlRow()

            loadingOr(useHomeSkeleton: homeSegment == .overview) {
                Group {
                    switch homeSegment {
                    case .overview:
                        OverviewHubView(
                            transactions: appState.filteredTransactions,
                            allTransactions: appState.transactions,
                            fuelTransactions: appState.fuelBalanceTransactions,
                            employees: appState.employees,
                            settings: appState.settings,
                            dateFilter: appState.dateFilter,
                            greetingName: auth.currentAdmin?.displayName,
                            transactionsRevision: appState.transactionsRevision
                        )
                        .refreshable { await appState.refresh(forceFull: true) }
                        .transition(.opacity)
                    case .worklog:
                        ScrollView {
                            WorkLogView(
                                transactions: appState.transactions,
                                employees: appState.employees,
                                settings: appState.settings
                            )
                            .padding(AppTheme.spaceLG)
                        }
                        .refreshable { await appState.refresh(forceFull: true) }
                        .scrollContentBackground(.hidden)
                        .transition(.opacity)
                    case .reports:
                        reportsHub
                            .refreshable { await appState.refresh(forceFull: true) }
                            .transition(.opacity)
                    case .calendar:
                        ScrollView {
                            CalendarV3View(
                                transactions: appState.transactions,
                                employees: appState.employees,
                                onDaySelected: applyHomeCalendarDay
                            )
                            .padding(AppTheme.spaceLG)
                        }
                        .refreshable { await appState.refresh(forceFull: true) }
                        .scrollContentBackground(.hidden)
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? .none : .smooth(duration: 0.22), value: homeSegment)
            }
        }
        .background(DashboardBackground())
        .navigationTitle(appState.settings.appName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                opsMenuButton
            }
            headerToolbar
        }
        .sheet(isPresented: $showHomeCustomDatePicker) {
            homeCustomDatePickerSheet
        }
    }

    private var opsMenuButton: some View {
        Button {
            openOpsMenu()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.9))
        .accessibilityLabel("เปิดเมนูงานประจำวัน")
    }

    /// Sync Home date filter to the day tapped on the embedded calendar.
    private func applyHomeCalendarDay(_ ymd: String) {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let day = DashboardAggregations.gregorian.date(from: comps) else { return }
        appState.datePreset = .custom
        appState.customStart = day
        appState.customEnd = day
    }

    private var homeActiveDay: Date {
        let cal = DashboardAggregations.gregorian
        let today = cal.startOfDay(for: Date())
        switch appState.datePreset {
        case .today:
            return today
        case .yesterday:
            return cal.date(byAdding: .day, value: -1, to: today) ?? today
        case .custom:
            return cal.startOfDay(for: appState.customEnd)
        default:
            return today
        }
    }

    private var canStepHomeForward: Bool {
        let cal = DashboardAggregations.gregorian
        let today = cal.startOfDay(for: Date())
        return homeActiveDay < today
    }

    private var canStepHomeBackward: Bool {
        let cal = DashboardAggregations.gregorian
        let earliest = cal.date(byAdding: .day, value: -90, to: cal.startOfDay(for: Date())) ?? Date()
        return homeActiveDay > earliest
    }

    private func stepHomeDay(by delta: Int) {
        let cal = DashboardAggregations.gregorian
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let earliest = cal.date(byAdding: .day, value: -90, to: today) ?? today
        guard let candidate = cal.date(byAdding: .day, value: delta, to: homeActiveDay) else { return }
        let clamped = min(max(candidate, earliest), today)
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.24)) {
            if cal.isDate(clamped, inSameDayAs: today) {
                appState.datePreset = .today
            } else if cal.isDate(clamped, inSameDayAs: yesterday) {
                appState.datePreset = .yesterday
            } else {
                appState.datePreset = .custom
                appState.customStart = clamped
                appState.customEnd = clamped
            }
        }
    }

    private var homeCustomDateLabel: String {
        if appState.datePreset == .custom {
            return ReportDateScope.shortThaiDate(appState.customEnd)
        }
        return "เลือกวัน"
    }

    private var homeDateFeedbackKey: String {
        "\(appState.datePreset.rawValue)-\(appState.dateFilter.start)-\(appState.dateFilter.end)"
    }

    private var homeCustomDatePickerSheet: some View {
        let earliest = DashboardAggregations.gregorian.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    "เลือกวันที่",
                    selection: $homeCustomDraft,
                    in: earliest...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
            .navigationTitle("เลือกวันที่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { showHomeCustomDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เลือก") {
                        appState.datePreset = .custom
                        appState.customStart = homeCustomDraft
                        appState.customEnd = homeCustomDraft
                        showHomeCustomDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Full-width Pro segment bar + contextual 1-tap date stepper bar for the Overview segment.
    private func homeControlRow() -> some View {
        VStack(spacing: 10) {
            HomeSegmentPill(selection: $homeSegment)

            if homeSegment == .overview {
                homeDateBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: 1)
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.24), value: homeSegment)
    }

    private var homeDateBar: some View {
        HStack(spacing: 5) {
            dayStepButton(systemImage: "chevron.left", enabled: canStepHomeBackward, label: "วันก่อนหน้า") {
                stepHomeDay(by: -1)
            }

            homeQuickDateChip(
                title: "วันนี้",
                isSelected: appState.datePreset == .today
            ) {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.24)) {
                    appState.datePreset = .today
                }
            }

            homeQuickDateChip(
                title: "เมื่อวาน",
                isSelected: appState.datePreset == .yesterday
            ) {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.24)) {
                    appState.datePreset = .yesterday
                }
            }

            homeQuickDateChip(
                title: homeCustomDateLabel,
                systemImage: "calendar",
                isSelected: appState.datePreset == .custom
            ) {
                homeCustomDraft = homeActiveDay
                showHomeCustomDatePicker = true
            }

            dayStepButton(systemImage: "chevron.right", enabled: canStepHomeForward, label: "วันถัดไป") {
                stepHomeDay(by: 1)
            }

            Spacer(minLength: 2)

            homeSyncStatusPill
        }
        .sensoryFeedback(.selection, trigger: homeDateFeedbackKey)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: manualSyncHaptic)
    }

    private func dayStepButton(
        systemImage: String,
        enabled: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.inkSecondary : AppTheme.inkMuted.opacity(0.35))
                .frame(width: 26, height: 26)
                .background(Circle().fill(AppTheme.surface.opacity(enabled ? 0.85 : 0.45)))
                .overlay(Circle().strokeBorder(AppTheme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.88))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func homeQuickDateChip(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isSelected ? AppTheme.brand : AppTheme.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AppTheme.brand.opacity(0.13))
                        .overlay(Capsule().strokeBorder(AppTheme.brand.opacity(0.34), lineWidth: 1))
                        .matchedGeometryEffect(id: "homeDateActivePill", in: homeDateNS)
                } else {
                    Capsule()
                        .fill(AppTheme.surface.opacity(0.82))
                        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.94))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var homeSyncStatusPill: some View {
        if appState.isLoading || isManualSyncing {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppTheme.brand)
                Text("ซิงค์")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(.horizontal, 6)
        } else if let fetchedAt = appState.lastFetchedAt {
            Button {
                manualSyncHaptic += 1
                Task {
                    isManualSyncing = true
                    await appState.refresh(forceFull: true)
                    isManualSyncing = false
                }
            } label: {
                HStack(spacing: 3) {
                    HomeLivePulseDot(color: AppTheme.income, size: 5.5)
                    Text(Self.syncTimeFormatter.string(from: fetchedAt))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppTheme.surface.opacity(0.7)))
                .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 0.75))
            }
            .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.92))
            .accessibilityLabel("อัปเดตล่าสุด \(Self.syncTimeFormatter.string(from: fetchedAt)) แตะเพื่อซิงค์ข้อมูลใหม่")
        }
    }

    // MARK: - Realtime

    private func realtimeBoard(mode: RealtimeBoardMode) -> some View {
        loadingOr {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    RealtimeV4View(
                        transactions: appState.transactions,
                        transactionsByDay: appState.transactionsByDay,
                        employees: appState.employees,
                        settings: appState.settings,
                        transactionsRevision: appState.transactionsRevision,
                        mode: mode,
                        isRealtimeTabActive: isRealtimeTabActive,
                        isBoardVisible: isRealtimeBoardActive(mode),
                        focusDate: $realtimeFocusDate
                    )
                }
                .padding(AppTheme.spaceLG)
            }
            .refreshable { await appState.refresh(forceFull: true) }
            .scrollContentBackground(.hidden)
        }
        .background(RealtimeV4Palette.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            headerControlsOverlay
        }
    }

    // MARK: - อัพเดตงาน (feed + tasks)

    private var feedBadge: Int {
        feedStore.unreadCount + taskStore.inboxCount
    }

    private var tasksTab: some View {
        FeedHubView()
            .toolbar { headerToolbar }
    }

    // MARK: - Reports hub

    private var reportsHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MobileDailyAuditCard(
                    transactions: appState.transactions,
                    employees: appState.employees
                )

                reportsSummaryStrip

                reportsSection(
                    title: "รายการบันทึกทั้งหมด",
                    subtitle: "ค้นหาและตรวจสอบธุรกรรมย้อนหลัง"
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
                    title: "รายงานตามหมวด",
                    subtitle: "สรุปวันนี้ · แตะเพื่อดูรายละเอียด"
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
                    settings: appState.settings,
                    stockTransactions: appState.fuelBalanceTransactions
                )
                NavigationLink {
                    categoryDetail(type)
                } label: {
                    categorySummaryCard(type: type, summary: summary)
                }
                .buttonStyle(HomeTactileButtonStyle(pressedScale: 0.96))
            }
        }
        .padding(12)
    }

    private func categorySummaryCard(type: CategoryReportType, summary: CategoryHubSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: type.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(type.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(type.accent.opacity(0.12))
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
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(summary.hasData ? AppTheme.ink : AppTheme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())

            Text(summary.secondary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceSoft.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.title) \(summary.primary) \(summary.secondary)")
    }

    private var reportsSummaryStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.brand.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("ศูนย์รายงาน")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(CategoryReportType.allCases.count) หมวดสรุปวันนี้")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("ค่าใช้จ่ายวันนี้")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                Text(categoryHubExpenseTodayLabel)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .contentTransition(.numericText())
            }
        }
        .padding(14)
        .homeCardSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ศูนย์รายงาน \(CategoryReportType.allCases.count) หมวด ค่าใช้จ่ายวันนี้ \(categoryHubExpenseTodayLabel)")
    }

    private var categoryHubExpenseTodayLabel: String {
        let day = todayKey
        let types: [CategoryReportType] = [.labor, .vehicle, .fuel, .land]
        let total = types.reduce(0.0) { sum, type in
            let dayTx = appState.transactions.filter {
                String($0.date.prefix(10)) == day && type.matches($0)
            }
            switch type {
            case .labor:
                return sum + DashboardAggregations.laborCostForDay(
                    dayLaborTx: dayTx,
                    employees: appState.employees
                )
            case .vehicle:
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

    private func reportsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: title, trailing: subtitle)

            VStack(spacing: 0) {
                content()
            }
            .homeCardSurface()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .sensoryFeedback(.impact(flexibility: .soft), trigger: appearanceMode)
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
    private func loadingOr<Content: View>(
        useHomeSkeleton: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if appState.isLoading && appState.transactions.isEmpty {
            if useHomeSkeleton {
                HomeOverviewSkeletonView()
            } else {
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
            }
        } else if let error = appState.errorMessage, appState.transactions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                EmptyStateView(
                    title: "โหลดไม่สำเร็จ",
                    message: "\(error)\n\nHost: \(appState.supabaseHost)",
                    systemImage: "wifi.exclamationmark"
                )
                Button("ลองอีกครั้ง") {
                    Task { await appState.refresh(forceFull: true) }
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
                    Task { await appState.refresh(forceFull: true) }
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

    private static let trackFill = Color(light: Color(hex: "#E8EEF6"), dark: Color(hex: "#0E1627"))
    private static let thumbFill = Color(light: Color.white, dark: Color(hex: "#1E293B"))
    private static let thumbStroke = Color(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.10))

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HomeSegment.allCases) { seg in
                let isSelected = selection == seg
                Button {
                    withAnimation(.snappy(duration: 0.26)) { selection = seg }
                } label: {
                    Text(seg.rawValue)
                        .font(.footnote.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Self.thumbFill)
                                    .overlay(Capsule().strokeBorder(Self.thumbStroke, lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
                                    .matchedGeometryEffect(id: "homeSegThumb", in: pillNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Self.trackFill))
        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
