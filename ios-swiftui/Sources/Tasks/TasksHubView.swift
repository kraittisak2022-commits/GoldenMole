import SwiftUI
import UIKit

/// Time window shown by the "งาน" tab.
private enum TasksSegment: String, CaseIterable, Identifiable {
    case today = "วันนี้"
    case week = "สัปดาห์"
    case month = "เดือน"
    case year = "ปี"
    case calendar = "ปฏิทิน"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .week: return "calendar.day.timeline.left"
        case .month: return "calendar"
        case .year: return "calendar.badge.clock"
        case .calendar: return "calendar.circle.fill"
        }
    }
}

/// Ownership / visibility filter applied on top of the time window.
private enum TaskFilterChip: String, CaseIterable, Identifiable {
    case all = "ฟีดทีม"
    case mine = "ที่ฉันแจ้ง"
    case assigned = "ถึงฉัน"
    case shared = "สาธารณะ"
    case personal = "ส่วนตัว"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "bubble.left.and.bubble.right.fill"
        case .mine: return "megaphone.fill"
        case .assigned: return "bell.badge.fill"
        case .shared: return "person.3.fill"
        case .personal: return "lock.fill"
        }
    }
}

/// Client-side feed ordering (no backend change).
private enum TaskFeedSort: String, CaseIterable, Identifiable {
    case smart = "อัจฉริยะ"
    case deadline = "เดดไลน์"
    case priority = "ความสำคัญ"
    case newest = "ล่าสุด"

    var id: String { rawValue }
}

/// The "งาน" tab — community work board for posting and tracking team tasks.
struct TasksHubView: View {
    @Environment(TaskStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var segment: TasksSegment = .today
    @State private var chip: TaskFilterChip = .all
    @State private var feedSort: TaskFeedSort = .smart
    @State private var selectedDay = DashboardAggregations.todayYMD()
    @State private var editorTarget: EditorTarget?
    @State private var statusTarget: WorkTask?

    private struct EditorTarget: Identifiable {
        let id: String
        let task: WorkTask
        let isNew: Bool
    }

    // MARK: - Derived data

    private var adminId: String { auth.currentAdmin?.id ?? "" }
    private var adminName: String? { auth.currentAdmin?.displayName }
    private var today: String { DashboardAggregations.todayYMD() }

    /// Everything the signed-in admin may see, narrowed by the active filter chip.
    private var scopedTasks: [WorkTask] {
        store.visible(to: adminId).filter { task in
            switch chip {
            case .all: return true
            case .mine: return task.ownerAdminId == adminId
            case .assigned: return task.assigneeAdminId == adminId
            case .shared: return task.visibility == .shared
            case .personal: return task.visibility == .personal
            }
        }
    }

    /// Inclusive `yyyy-MM-dd` window for the active segment.
    private var window: DateFilter {
        let cal = DashboardAggregations.gregorian
        switch segment {
        case .today:
            return DateFilter(start: today, end: today)
        case .week:
            return DateFilter(start: today, end: DashboardAggregations.shiftDateStr(today, deltaDays: 6))
        case .month:
            let comps = cal.dateComponents([.year, .month], from: Date())
            guard let first = cal.date(from: comps),
                  let range = cal.range(of: .day, in: .month, for: first)
            else { return DateFilter(start: today, end: today) }
            let start = DashboardAggregations.formatYMD(first)
            return DateFilter(start: start, end: DashboardAggregations.shiftDateStr(start, deltaDays: range.count - 1))
        case .year:
            let year = cal.component(.year, from: Date())
            return DateFilter(start: "\(year)-01-01", end: "\(year)-12-31")
        case .calendar:
            return DateFilter(start: selectedDay, end: selectedDay)
        }
    }

    /// True when the active window covers today — only then do we surface carry-overs.
    private var windowIncludesToday: Bool {
        window.start <= today && window.end >= today
    }

    private var carryOverTasks: [WorkTask] {
        guard windowIncludesToday else { return [] }
        let carriedIds = Set(store.carryOverTasks(to: today, adminId: adminId).map(\.id))
        return scopedTasks.filter { carriedIds.contains($0.id) }
    }

    private var listedTasks: [WorkTask] {
        let range = window
        var items = scopedTasks.filter { $0.dueDate >= range.start && $0.dueDate <= range.end }
        if windowIncludesToday {
            let existing = Set(items.map(\.id))
            items.append(contentsOf: carryOverTasks.filter { !existing.contains($0.id) })
        }
        return sortFeed(items)
    }

    private struct FeedGroup: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let tint: Color
        let tasks: [WorkTask]
    }

    private var feedGroups: [FeedGroup] {
        let items = listedTasks
        guard !items.isEmpty else { return [] }

        let overdue = items.filter { !$0.isDone && $0.isPastDeadline() }
        let carried = items.filter { task in
            !task.isDone && !overdue.contains(where: { $0.id == task.id })
                && task.carryOverDays(to: today) != nil
        }
        let urgent = items.filter { task in
            !task.isDone
                && !overdue.contains(where: { $0.id == task.id })
                && !carried.contains(where: { $0.id == task.id })
                && (task.priority == .urgent || task.priority == .high)
        }
        let active = items.filter { task in
            task.status == .inProgress
                && !overdue.contains(where: { $0.id == task.id })
                && !carried.contains(where: { $0.id == task.id })
                && !urgent.contains(where: { $0.id == task.id })
        }
        let waiting = items.filter { task in
            task.status == .todo
                && !overdue.contains(where: { $0.id == task.id })
                && !carried.contains(where: { $0.id == task.id })
                && !urgent.contains(where: { $0.id == task.id })
        }
        let done = items.filter(\.isDone)

        var groups: [FeedGroup] = []
        if !overdue.isEmpty {
            groups.append(FeedGroup(id: "overdue", title: "เลยเดดไลน์", systemImage: "exclamationmark.triangle.fill", tint: AppTheme.expense, tasks: overdue))
        }
        if !carried.isEmpty {
            groups.append(FeedGroup(id: "carry", title: "ยกมาจากวันก่อน", systemImage: "arrow.uturn.forward", tint: AppTheme.warning, tasks: carried))
        }
        if !urgent.isEmpty {
            groups.append(FeedGroup(id: "urgent", title: "ด่วน / สำคัญ", systemImage: "flame.fill", tint: AppTheme.warning, tasks: urgent))
        }
        if !active.isEmpty {
            groups.append(FeedGroup(id: "active", title: "กำลังทำ", systemImage: "bolt.fill", tint: AppTheme.info, tasks: active))
        }
        if !waiting.isEmpty {
            groups.append(FeedGroup(id: "waiting", title: "รอเริ่ม", systemImage: "circle.dashed", tint: AppTheme.brand, tasks: waiting))
        }
        if !done.isEmpty {
            groups.append(FeedGroup(id: "done", title: "ปิดแล้ว", systemImage: "checkmark.seal.fill", tint: AppTheme.income, tasks: done))
        }
        return groups
    }

    private func sortFeed(_ items: [WorkTask]) -> [WorkTask] {
        switch feedSort {
        case .smart:
            return TaskStore.sorted(items)
        case .deadline:
            return items.sorted { a, b in
                let ad = a.deadlineDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                let bd = b.deadlineDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude
                if ad != bd { return ad < bd }
                return a.dueDate < b.dueDate
            }
        case .priority:
            let rank: [TaskPriority: Int] = [.urgent: 0, .high: 1, .normal: 2, .low: 3]
            return items.sorted { a, b in
                let ar = rank[a.priority] ?? 9
                let br = rank[b.priority] ?? 9
                if ar != br { return ar < br }
                return a.dueDate < b.dueDate
            }
        case .newest:
            return items.sorted { a, b in
                let ac = a.createdAt ?? ""
                let bc = b.createdAt ?? ""
                if ac != bc { return ac > bc }
                return a.title < b.title
            }
        }
    }

    private func chipCount(_ item: TaskFilterChip) -> Int {
        let base = store.visible(to: adminId)
        switch item {
        case .all: return base.count
        case .mine: return base.filter { $0.ownerAdminId == adminId }.count
        case .assigned: return base.filter { $0.assigneeAdminId == adminId }.count
        case .shared: return base.filter { $0.visibility == .shared }.count
        case .personal: return base.filter { $0.visibility == .personal }.count
        }
    }

    private var listedOpenCount: Int { listedTasks.filter { !$0.isDone }.count }
    private var listedUrgentCount: Int {
        listedTasks.filter { !$0.isDone && ($0.priority == .urgent || $0.priority == .high || $0.isPastDeadline()) }.count
    }
    private var listedDoneCount: Int { listedTasks.filter(\.isDone).count }

    private var focusTasks: [WorkTask] {
        store.focusTasks(on: today, adminId: adminId)
    }

    private var inboxTasks: [WorkTask] {
        store.inboxTasks()
    }

    /// Today's scope tasks plus unfinished carry-overs — what the hero card counts.
    private var todayTasks: [WorkTask] {
        let day = store.dayTasks(on: today, adminId: adminId)
        let carried = store.carryOverTasks(to: today, adminId: adminId)
        let existing = Set(day.map(\.id))
        return TaskStore.sorted(day + carried.filter { !existing.contains($0.id) })
    }

    private var doneToday: Int { todayTasks.filter(\.isDone).count }
    private var inProgressToday: Int { todayTasks.filter { $0.status == .inProgress }.count }
    private var openToday: Int { todayTasks.filter { $0.status == .todo }.count }
    private var carryOverCount: Int { store.carryOverTasks(to: today, adminId: adminId).count }
    private var livePulseCount: Int { openToday + inProgressToday + inboxTasks.count }

    private var todayProgress: Double {
        guard !todayTasks.isEmpty else { return 0 }
        return Double(doneToday) / Double(todayTasks.count)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                communityHero
                composerPrompt
                segmentPill

                if store.isLoading && store.tasks.isEmpty {
                    ProgressView("กำลังโหลดกระดานงาน…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                if let error = store.errorMessage {
                    errorBanner(error)
                }

                if !inboxTasks.isEmpty {
                    inboxSection
                }

                if segment == .today, !focusTasks.isEmpty {
                    focusSection
                }

                if segment == .calendar {
                    calendarSection
                }

                feedWindowKPI
                listSection
            }
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                DashboardBackground()
                RadialGradient(
                    colors: [AppTheme.brand.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 320
                )
                .ignoresSafeArea()
            }
        }
        .refreshable { await store.load() }
        .overlay(alignment: .bottomTrailing) { addButton }
        .navigationTitle("กระดานงาน")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.currentAdminId = adminId
            await store.loadIfNeeded()
        }
        .sheet(item: $editorTarget) { target in
            TaskEditorSheet(
                task: target.task,
                isNew: target.isNew,
                admins: store.admins,
                onSave: { saved in Task { await store.saveAll(saved, adminId: adminId) } },
                onDelete: { removed in Task { await store.delete(removed) } }
            )
            .presentationDetents([.large, .fraction(0.92)])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $statusTarget) { target in
            TaskStatusSheet(task: target) { picked in
                Task { await store.setStatus(target, to: picked) }
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .alert("ปักโฟกัสไม่ได้", isPresented: noticeBinding) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(store.noticeMessage ?? "")
        }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { store.noticeMessage != nil },
            set: { if !$0 { store.noticeMessage = nil } }
        )
    }

    // MARK: - Community hero

    private var communityHero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(hex: "#042F36"),
                    AppTheme.brandDark,
                    AppTheme.brandMid,
                    Color(hex: "#0E7490")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 200, height: 200)
                .blur(radius: 28)
                .offset(x: 210, y: -70)
            Circle()
                .fill(AppTheme.cyan.opacity(0.28))
                .frame(width: 120, height: 120)
                .blur(radius: 22)
                .offset(x: -40, y: 130)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("COMMUNITY BOARD")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.6)
                            if livePulseCount > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(hex: "#4ADE80"))
                                        .frame(width: 6, height: 6)
                                        .shadow(
                                            color: reduceMotion ? .clear : Color(hex: "#4ADE80").opacity(0.8),
                                            radius: reduceMotion ? 0 : 4
                                        )
                                    Text("\(livePulseCount) ไลฟ์")
                                        .font(.system(size: 10, weight: .bold))
                                        .contentTransition(.numericText())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                            }
                        }
                        .foregroundStyle(.white.opacity(0.72))

                        Text(heroHeadline)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.opacity)

                        Text(DashboardAggregations.thaiDateLong(today))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))

                        Text("แจ้งงาน · มอบหมาย · ปิดงานเป็นทีม")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))

                        if carryOverCount > 0 {
                            Label("ยกมา \(carryOverCount) งานจากวันก่อน", systemImage: "arrow.uturn.forward")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: "#FFEDD5"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    progressRing
                }

                HStack(spacing: 0) {
                    heroStat(title: "ปิดแล้ว", value: doneToday, tint: Color(hex: "#A7F3D0"))
                    heroDivider
                    heroStat(title: "กำลังทำ", value: inProgressToday, tint: Color(hex: "#FDE68A"))
                    heroDivider
                    heroStat(title: "รอเริ่ม", value: openToday, tint: Color(hex: "#CFFAFE"))
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: AppTheme.brand.opacity(0.22), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("กระดานงานวันนี้ ทั้งหมด \(todayTasks.count) เสร็จแล้ว \(doneToday)")
    }

    private var heroHeadline: String {
        if openToday + inProgressToday == 0, !todayTasks.isEmpty {
            return "ทีมเคลียร์งานครบแล้ว"
        }
        if !inboxTasks.isEmpty {
            return "มีงานใหม่ถึงคุณ"
        }
        if openToday > 0 {
            return "ฟีดงานที่ต้องตาม"
        }
        if inProgressToday > 0 {
            return "ทีมกำลังเดินหน้า"
        }
        return "พร้อมแจ้งงานใหม่"
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, todayProgress)))
                .stroke(
                    AngularGradient(
                        colors: [.white.opacity(0.55), .white, AppTheme.cyan],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(todayTasks.isEmpty ? "—" : "\(Int(round(todayProgress * 100)))%")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(todayTasks.isEmpty ? "ว่าง" : "\(doneToday)/\(todayTasks.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .minimumScaleFactor(0.6)
        }
        .frame(width: 70, height: 70)
        .animation(.snappy(duration: 0.35), value: todayProgress)
        .accessibilityHidden(true)
    }

    private func heroStat(title: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.weight(.heavy))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    // MARK: - Composer prompt

    private var composerPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                openComposer()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.brand, AppTheme.brandMid],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        Text(Self.initials(from: adminName ?? "ฉัน"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("แจ้งงานให้ทีม…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("หลายบรรทัด · มอบหมาย · เดดไลน์ · เตือน")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.brand))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.surface)
                        .shadow(color: AppTheme.cardShadow.opacity(0.35), radius: 8, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AppTheme.brand.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("แจ้งงานใหม่ให้ทีม")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    composerQuickChip("ด่วนวันนี้", systemImage: "flame.fill") {
                        openComposer(priority: .urgent, due: today)
                    }
                    composerQuickChip("มอบหมายถึงฉัน", systemImage: "person.fill.checkmark") {
                        openComposer(assignSelf: true)
                    }
                    composerQuickChip("งานสัปดาห์", systemImage: "calendar") {
                        openComposer(scope: .weekly)
                    }
                    composerQuickChip("ส่วนตัว", systemImage: "lock.fill") {
                        openComposer(visibility: .personal)
                    }
                }
            }
        }
    }

    private func composerQuickChip(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(AppTheme.brand)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(AppTheme.brand.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls

    private var segmentPill: some View {
        VStack(alignment: .leading, spacing: 10) {
            TasksSegmentPill(selection: $segment)
            filterChips
        }
    }

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskFilterChip.allCases) { item in
                        let isActive = chip == item
                        let count = chipCount(item)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { chip = item }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 10, weight: .bold))
                                Text(item.rawValue)
                                    .font(.caption.weight(.semibold))
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(isActive ? Color.white.opacity(0.22) : AppTheme.surfaceSoft)
                                        )
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(isActive ? .white : AppTheme.inkSecondary)
                            .background {
                                if isActive {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.brand, AppTheme.brandMid],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                } else {
                                    Capsule().fill(AppTheme.surface)
                                }
                            }
                            .overlay(
                                Capsule().strokeBorder(
                                    isActive ? Color.clear : AppTheme.hairline,
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: isActive ? AppTheme.brand.opacity(0.28) : .clear, radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("เรียง")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                    ForEach(TaskFeedSort.allCases) { item in
                        let on = feedSort == item
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { feedSort = item }
                        } label: {
                            Text(item.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(on ? .white : AppTheme.inkMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(on ? AppTheme.info : AppTheme.surfaceSoft))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.expense)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.expense.opacity(0.1))
        )
    }

    // MARK: - Assignment inbox

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("แจ้งเตือนถึงคุณ", systemImage: "bell.badge.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                Text("\(inboxTasks.count) ใหม่")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.info))
            }

            Text("งานที่มอบหมายให้คุณแล้วยังไม่ได้รับทราบ")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)

            HStack {
                Spacer(minLength: 0)
                Button {
                    let all = inboxTasks
                    Task { await store.markAssignmentSeen(all) }
                } label: {
                    Label("รับทราบทั้งหมด", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(AppTheme.brand)
            }

            VStack(spacing: 10) {
                ForEach(inboxTasks) { task in
                    inboxRow(task)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow.opacity(0.35), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.info.opacity(0.25), lineWidth: 1)
        )
    }

    private func inboxRow(_ task: WorkTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                personAvatar(name: task.ownerName ?? "ทีม", accent: AppTheme.info)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.ownerName?.isEmpty == false ? (task.ownerName ?? "ทีม") : "ทีม")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("แจ้งงานถึงคุณ")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.info)
                    }
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    Text(inboxSubtitle(task))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await store.markAssignmentSeen([task])
                        await store.setStatus(task, to: .inProgress)
                    }
                } label: {
                    Label("รับทราบ+เริ่ม", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
                .controlSize(.small)

                Button {
                    Task { await store.markAssignmentSeen([task]) }
                } label: {
                    Text("รับทราบ")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.info.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture { editorTarget = EditorTarget(id: task.id, task: task, isNew: false) }
    }

    private func inboxSubtitle(_ task: WorkTask) -> String {
        var parts: [String] = []
        if let assigned = task.assignedDate {
            parts.append(TaskDates.shortTime(assigned))
        }
        parts.append("กำหนด \(DashboardAggregations.dayLabel(task.dueDate))")
        return parts.joined(separator: " · ")
    }

    // MARK: - Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ปักหมุดสำคัญ", systemImage: "pin.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                PillBadge(
                    text: "\(focusTasks.count)/\(TaskStore.focusLimit)",
                    color: focusTasks.count >= TaskStore.focusLimit ? AppTheme.warning : AppTheme.brand
                )
            }
            Text("งานด่วนที่ทีมควรโฟกัสก่อน")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)

            VStack(spacing: 8) {
                ForEach(Array(focusTasks.enumerated()), id: \.element.id) { index, task in
                    focusRow(index: index, task: task)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow.opacity(0.3), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.brand.opacity(0.18), lineWidth: 1)
        )
    }

    private func focusRow(index: Int, task: WorkTask) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [AppTheme.brandDark, AppTheme.brand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )

            statusButton(task)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .strikethrough(task.isDone, color: AppTheme.inkMuted)
                    .lineLimit(2)
                Text(task.priority.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(task.priority.color)
            }

            Spacer(minLength: 0)

            Button {
                Task { await store.toggleFocus(task, adminId: adminId) }
            } label: {
                Image(systemName: "pin.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เอา \(task.title) ออกจากโฟกัส")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .contentShape(Rectangle())
        .onTapGesture { editorTarget = EditorTarget(id: task.id, task: task, isNew: false) }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ปฏิทินงานชุมชน")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("แตะวันเพื่อดูฟีดงาน · จุดส้ม = ยังค้าง")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppTheme.brand.opacity(0.14)))
            }

            TaskCalendarView(tasks: scopedTasks, selectedDay: $selectedDay)

            let dayItems = listedTasks
            HStack(spacing: 8) {
                feedKPITile("วันนี้เลือก", dayItems.count, AppTheme.ink)
                feedKPITile("ค้าง", dayItems.filter { !$0.isDone }.count, AppTheme.warning)
                feedKPITile(
                    "ด่วน",
                    dayItems.filter { !$0.isDone && ($0.priority == .urgent || $0.priority == .high || $0.isPastDeadline()) }.count,
                    AppTheme.expense
                )
            }
        }
        .padding(AppTheme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow.opacity(0.35), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Feed list

    private var feedWindowKPI: some View {
        HStack(spacing: 8) {
            feedKPITile("ทั้งหมด", listedTasks.count, AppTheme.ink)
            feedKPITile("ค้าง", listedOpenCount, AppTheme.warning)
            feedKPITile("ด่วน", listedUrgentCount, AppTheme.expense)
            feedKPITile("ปิดแล้ว", listedDoneCount, AppTheme.income)
        }
    }

    private func feedKPITile(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(listTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(listSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: listSystemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.brand.opacity(0.12)))
            }

            if listedTasks.isEmpty {
                EmptyStateView(
                    title: emptyTitle,
                    message: chip == .all
                        ? "แตะ «แจ้งงาน» หรือชิปด่วนด้านบน เพื่อโพสต์งานให้ทีม"
                        : "ลองเปลี่ยนตัวกรองเป็น «ฟีดทีม» เพื่อดูงานของทุกคน",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(feedGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: group.systemImage)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(group.tint)
                                Text(group.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("\(group.tasks.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(group.tint))
                                Spacer(minLength: 0)
                            }

                            ForEach(group.tasks) { task in
                                feedPost(task)
                            }
                        }
                    }
                }
                .animation(.snappy(duration: 0.25), value: listedTasks.map(\.id))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private var listSystemImage: String {
        switch segment {
        case .today: return "bubble.left.and.bubble.right.fill"
        case .calendar: return "calendar.badge.clock"
        default: return "list.bullet.rectangle.portrait.fill"
        }
    }

    private var emptyTitle: String {
        switch segment {
        case .today: return "ยังไม่มีใครแจ้งงานวันนี้"
        case .calendar: return "วันที่เลือกยังว่างอยู่"
        default: return "ยังไม่มีงานในช่วงนี้"
        }
    }

    private var listTitle: String {
        switch segment {
        case .today: return "ฟีดงานวันนี้"
        case .week: return "ฟีด 7 วันข้างหน้า"
        case .month: return "ฟีดเดือนนี้"
        case .year: return "ฟีดปีนี้"
        case .calendar: return "ฟีด · \(DashboardAggregations.thaiDateLong(selectedDay))"
        }
    }

    private var listSubtitle: String {
        let open = listedTasks.filter { !$0.isDone }.count
        if listedTasks.isEmpty { return "รอโพสต์แรกของทีม" }
        if open == 0 { return "\(listedTasks.count) โพสต์ · ปิดครบแล้ว" }
        return "\(listedTasks.count) โพสต์ · ค้าง \(open)"
    }

    private func feedPost(_ task: WorkTask) -> some View {
        let poster = posterName(for: task)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                personAvatar(name: poster, accent: Self.avatarColor(for: poster))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(poster)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                        if task.isFocus {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.brand)
                        }
                        if task.isNewAssignment(for: adminId) {
                            Text("ใหม่")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.info))
                        }
                    }
                    Text(postMetaLine(task))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                statusButton(task)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(task.isDone ? AppTheme.inkMuted : AppTheme.ink)
                    .strikethrough(task.isDone, color: AppTheme.inkMuted)
                    .multilineTextAlignment(.leading)

                if let note = task.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    metaChip(text: task.priority.label, systemImage: task.priority.systemImage, color: task.priority.color)
                    if let days = task.carryOverDays(to: today) {
                        metaChip(text: "ยกมา \(days) วัน", systemImage: "arrow.uturn.forward", color: AppTheme.warning)
                    }
                    if task.scope != .daily {
                        metaChip(text: task.scope.shortLabel, systemImage: task.scope.systemImage, color: AppTheme.slate)
                    }
                    if let deadline = task.deadlineDate {
                        metaChip(
                            text: deadlineLabel(deadline, isPast: task.isPastDeadline()),
                            systemImage: "clock.fill",
                            color: task.isPastDeadline() ? AppTheme.expense : AppTheme.info
                        )
                    }
                    if task.visibility == .personal {
                        metaChip(text: "ส่วนตัว", systemImage: "lock.fill", color: AppTheme.slate)
                    } else {
                        metaChip(text: "ทีม", systemImage: "person.2.fill", color: AppTheme.brand)
                    }
                    if task.remindDate != nil {
                        metaChip(text: "เตือน", systemImage: "bell.fill", color: AppTheme.info)
                    }
                }
            }

            HStack(spacing: 10) {
                Label(DashboardAggregations.dayLabel(task.dueDate), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)

                if let assignee = task.assigneeName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !assignee.isEmpty
                {
                    Label(assignee, systemImage: "person.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                pinButton(task)
            }

            if !task.isDone {
                HStack(spacing: 8) {
                    if task.status == .todo {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task {
                                if task.isNewAssignment(for: adminId) {
                                    await store.markAssignmentSeen([task])
                                }
                                await store.setStatus(task, to: .inProgress)
                            }
                        } label: {
                            Label("เริ่มทำ", systemImage: "play.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.info)
                        .controlSize(.small)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await store.setStatus(task, to: .done) }
                    } label: {
                        Label("ปิดงาน", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.income)
                    .controlSize(.small)

                    if task.isNewAssignment(for: adminId) {
                        Button {
                            Task { await store.markAssignmentSeen([task]) }
                        } label: {
                            Text("รับทราบ")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)

                    Button {
                        statusTarget = task
                    } label: {
                        Text("สถานะ")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(AppTheme.inkMuted)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow.opacity(0.25), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    task.isDone ? AppTheme.hairline : task.priority.color.opacity(0.22),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(task.isDone ? AppTheme.inkMuted.opacity(0.35) : task.priority.color)
            .frame(width: 4)
            .accessibilityLabel("ความสำคัญ \(task.priority.label)")
        }
        .contentShape(Rectangle())
        .onTapGesture { editorTarget = EditorTarget(id: task.id, task: task, isNew: false) }
        .contextMenu {
            Button {
                editorTarget = EditorTarget(id: task.id, task: task, isNew: false)
            } label: {
                Label("แก้ไข", systemImage: "pencil")
            }
            Button {
                Task { await store.toggleFocus(task, adminId: adminId) }
            } label: {
                Label(
                    task.isFocus ? "เอาออกจากโฟกัส" : "ปักเป็นงานโฟกัส",
                    systemImage: task.isFocus ? "pin.slash" : "pin.fill"
                )
            }
            Button(role: .destructive) {
                Task { await store.delete(task) }
            } label: {
                Label("ลบงาน", systemImage: "trash")
            }
        }
    }

    private func posterName(for task: WorkTask) -> String {
        let owner = (task.ownerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty { return owner }
        if task.ownerAdminId == adminId { return adminName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "ฉัน" }
        return "ทีม"
    }

    private func postMetaLine(_ task: WorkTask) -> String {
        var parts: [String] = []
        if task.visibility == .shared {
            parts.append("โพสต์สาธารณะ")
        } else {
            parts.append("โพสต์ส่วนตัว")
        }
        if let created = task.createdAt.flatMap(TaskDates.parseISO) {
            parts.append(TaskDates.shortTime(created))
        } else {
            parts.append(DashboardAggregations.dayLabel(task.dueDate))
        }
        return parts.joined(separator: " · ")
    }

    private func personAvatar(name: String, accent: Color) -> some View {
        Text(Self.initials(from: name))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func pinButton(_ task: WorkTask) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await store.toggleFocus(task, adminId: adminId) }
        } label: {
            Image(systemName: task.isFocus ? "pin.fill" : "pin")
                .font(.caption)
                .foregroundStyle(task.isFocus ? AppTheme.brand : AppTheme.inkMuted.opacity(0.65))
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppTheme.surfaceSoft))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.isFocus
                            ? "เอา \(task.title) ออกจากโฟกัส"
                            : "ปัก \(task.title) เป็นงานโฟกัส")
    }

    private func statusButton(_ task: WorkTask) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            statusTarget = task
        } label: {
            Image(systemName: task.status.systemImage)
                .font(.title3)
                .foregroundStyle(task.status.color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(task.status.color.opacity(0.12)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title) สถานะ \(task.status.label) แตะเพื่อเลือกสถานะใหม่")
    }

    /// Relative wording so the chip reads as urgency, not as a raw timestamp.
    private func deadlineLabel(_ date: Date, isPast: Bool) -> String {
        let minutes = Int(abs(date.timeIntervalSinceNow) / 60)
        if isPast {
            if minutes < 60 { return "เลย \(max(1, minutes)) นาที" }
            if minutes < 60 * 24 { return "เลย \(minutes / 60) ชม." }
            return "เลย \(minutes / (60 * 24)) วัน"
        }
        if date > Date() {
            if minutes < 60 { return "เหลือ \(max(1, minutes)) นาที" }
            if minutes < 60 * 12 { return "เหลือ \(minutes / 60) ชม." }
        }
        let day = DashboardAggregations.formatYMD(date)
        return day == today
            ? "ถึง \(TaskDates.clockTime(date))"
            : "ถึง \(DashboardAggregations.dayLabel(day)) \(TaskDates.clockTime(date))"
    }

    private static let avatarPalette: [Color] = [
        AppTheme.brand, AppTheme.info, AppTheme.warning,
        AppTheme.income, AppTheme.cyan, AppTheme.brandMid
    ]

    /// Stable per-person tint so the same initials keep the same colour across rows.
    private static func avatarColor(for name: String) -> Color {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return AppTheme.brand }
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFF_FFFF }
        return avatarPalette[hash % avatarPalette.count]
    }

    private static func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = parts.map { String($0.prefix(1)).uppercased() }.joined()
        return letters.isEmpty ? String(trimmed.prefix(1)).uppercased() : letters
    }

    private func metaChip(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }

    // MARK: - Add

    private func openComposer(
        priority: TaskPriority = .normal,
        due: String? = nil,
        scope: TaskScope = .daily,
        visibility: TaskVisibility = .shared,
        assignSelf: Bool = false
    ) {
        let day = due ?? (segment == .calendar ? selectedDay : today)
        var draft = WorkTask.new(ownerAdminId: adminId, ownerName: adminName, dueDate: day)
        draft.priority = priority
        draft.scope = scope
        draft.visibility = visibility
        if assignSelf {
            draft.assigneeAdminId = adminId
            draft.assigneeName = adminName
        }
        editorTarget = EditorTarget(id: draft.id, task: draft, isNew: true)
    }

    private var addButton: some View {
        Button {
            openComposer()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .font(.body.weight(.bold))
                Text("แจ้งงาน")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.brand, AppTheme.brandMid],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: AppTheme.brand.opacity(0.42), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, AppTheme.spaceLG)
        .padding(.bottom, AppTheme.spaceLG)
        .accessibilityLabel("แจ้งงานใหม่")
    }
}

// MARK: - Segment pill

private struct TasksSegmentPill: View {
    @Binding var selection: TasksSegment
    @Namespace private var pillNS

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(TasksSegment.allCases) { option in
                    let isOn = selection == option
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { selection = option }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 11, weight: .bold))
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(isOn ? .white : AppTheme.inkMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.brand, AppTheme.brandMid],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "tasksSegThumb", in: pillNS)
                                    .shadow(color: AppTheme.brand.opacity(0.35), radius: 8, y: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(4)
        }
        .background(
            Capsule()
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow.opacity(0.5), radius: 8, y: 2)
        )
        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
