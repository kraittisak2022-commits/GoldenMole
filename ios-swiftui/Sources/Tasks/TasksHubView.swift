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
}

/// Ownership / visibility filter applied on top of the time window.
private enum TaskFilterChip: String, CaseIterable, Identifiable {
    case all = "ทั้งหมด"
    case mine = "ของฉัน"
    case assigned = "มอบให้ฉัน"
    case shared = "สาธารณะ"
    case personal = "ส่วนตัว"

    var id: String { rawValue }
}

/// The "งาน" tab — a to-do board scoped by day, week, month, year, or a month calendar.
struct TasksHubView: View {
    @Environment(TaskStore.self) private var store
    @Environment(AuthService.self) private var auth

    @State private var segment: TasksSegment = .today
    @State private var chip: TaskFilterChip = .all
    @State private var selectedDay = DashboardAggregations.todayYMD()
    @State private var editorTarget: EditorTarget?

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
        return TaskStore.sorted(items)
    }

    private var focusTasks: [WorkTask] {
        store.focusTasks(on: today, adminId: adminId)
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

    private var todayProgress: Double {
        guard !todayTasks.isEmpty else { return 0 }
        return Double(doneToday) / Double(todayTasks.count)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceXL) {
                heroCard
                segmentPill

                if let error = store.errorMessage {
                    errorBanner(error)
                }

                if segment == .today {
                    focusSection
                }

                if segment == .calendar {
                    SectionCard("ปฏิทินงาน", systemImage: "calendar") {
                        TaskCalendarView(tasks: scopedTasks, selectedDay: $selectedDay)
                    }
                }

                listSection
            }
            .padding(AppTheme.spaceLG)
            .padding(.bottom, 80)
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
        .refreshable { await store.load() }
        .overlay(alignment: .bottomTrailing) { addButton }
        .navigationTitle("งาน")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadIfNeeded() }
        .sheet(item: $editorTarget) { target in
            TaskEditorSheet(
                task: target.task,
                isNew: target.isNew,
                admins: store.admins,
                onSave: { saved in Task { await store.saveAll(saved, adminId: adminId) } },
                onDelete: { removed in Task { await store.delete(removed) } }
            )
            .presentationDetents([.medium, .large])
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

    // MARK: - Hero

    private var heroCard: some View {
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
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TASKS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("สิ่งที่ต้องทำวันนี้")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(DashboardAggregations.thaiDateLong(today))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                    progressRing
                }

                HStack(spacing: 10) {
                    heroChip(title: "เสร็จแล้ว", value: "\(doneToday)", tint: Color(hex: "#A7F3D0"))
                    heroChip(title: "กำลังทำ", value: "\(inProgressToday)", tint: Color(hex: "#FDE68A"))
                    heroChip(title: "ยังไม่ทำ", value: "\(openToday)", tint: Color(hex: "#CFFAFE"))
                    if carryOverCount > 0 {
                        heroChip(title: "ยกมา", value: "\(carryOverCount)", tint: Color(hex: "#FDBA74"))
                    }
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("งานวันนี้ ทั้งหมด \(todayTasks.count) เสร็จแล้ว \(doneToday)")
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(todayProgress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(round(todayProgress * 100)))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 54, height: 54)
        .animation(.snappy(duration: 0.3), value: todayProgress)
        .accessibilityHidden(true)
    }

    private func heroChip(title: String, value: String, tint: Color) -> some View {
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

    // MARK: - Controls

    private var segmentPill: some View {
        VStack(alignment: .leading, spacing: 10) {
            TasksSegmentPill(selection: $segment)
            filterChips
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilterChip.allCases) { item in
                    let isActive = chip == item
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { chip = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(isActive ? .white : AppTheme.brand)
                            .background(Capsule().fill(isActive ? AppTheme.brand : AppTheme.surfaceSoft))
                            .overlay(
                                Capsule().strokeBorder(
                                    isActive ? Color.clear : AppTheme.brand.opacity(0.3),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
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

    // MARK: - Focus

    private var focusSection: some View {
        SectionCard(
            "โฟกัส \(TaskStore.focusLimit) งานสำคัญ",
            systemImage: "target",
            subtitle: "เลือกงานที่ด่วนที่สุดของวันนี้มาทำก่อน"
        ) {
            HStack {
                Text("ปักไว้แล้ว")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer(minLength: 0)
                PillBadge(
                    text: "\(focusTasks.count)/\(TaskStore.focusLimit)",
                    color: focusTasks.count >= TaskStore.focusLimit ? AppTheme.warning : AppTheme.brand
                )
            }

            if focusTasks.isEmpty {
                EmptyStateView(
                    title: "ยังไม่ได้ปักงานสำคัญ",
                    message: "แตะไอคอนหมุดที่งานเพื่อปักเป็นงานโฟกัสของวันนี้",
                    systemImage: "target"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(focusTasks.enumerated()), id: \.element.id) { index, task in
                        focusRow(index: index, task: task)
                    }
                }
            }
        }
    }

    private func focusRow(index: Int, task: WorkTask) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(AppTheme.purple))

            statusButton(task)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .strikethrough(task.isDone, color: AppTheme.inkMuted)
                    .lineLimit(2)
                Text(task.priority.label)
                    .font(.caption2)
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .contentShape(Rectangle())
        .onTapGesture { editorTarget = EditorTarget(id: task.id, task: task, isNew: false) }
    }

    // MARK: - List

    private var listSection: some View {
        SectionCard(listTitle, systemImage: "list.bullet", subtitle: listSubtitle) {
            if listedTasks.isEmpty {
                EmptyStateView(
                    title: "ยังไม่มีงานในช่วงนี้",
                    message: "กดปุ่ม + มุมขวาล่างเพื่อเพิ่มงานใหม่",
                    systemImage: "checklist"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(listedTasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    private var listTitle: String {
        switch segment {
        case .today: return "งานวันนี้"
        case .week: return "7 วันข้างหน้า"
        case .month: return "เดือนนี้"
        case .year: return "ปีนี้"
        case .calendar: return DashboardAggregations.thaiDateLong(selectedDay)
        }
    }

    private var listSubtitle: String {
        let open = listedTasks.filter { !$0.isDone }.count
        return "\(listedTasks.count) งาน · ค้าง \(open)"
    }

    private func taskRow(_ task: WorkTask, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusButton(task)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(task.isDone ? AppTheme.inkMuted : AppTheme.ink)
                    .strikethrough(task.isDone, color: AppTheme.inkMuted)
                    .multilineTextAlignment(.leading)

                if let note = task.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    if let days = task.carryOverDays(to: today) {
                        metaChip(
                            text: "ยกมา \(days) วัน",
                            systemImage: "arrow.uturn.forward",
                            color: AppTheme.warning
                        )
                    }
                    metaChip(
                        text: task.priority.label,
                        systemImage: task.priority.systemImage,
                        color: task.priority.color
                    )
                    metaChip(
                        text: task.scope.shortLabel,
                        systemImage: task.scope.systemImage,
                        color: tint ?? AppTheme.slate
                    )
                    if let deadline = task.deadlineDate {
                        metaChip(
                            text: "ถึง \(TaskDates.clockTime(deadline))",
                            systemImage: "clock.fill",
                            color: task.isPastDeadline() ? AppTheme.expense : AppTheme.info
                        )
                    }
                    if task.visibility == .personal {
                        metaChip(text: "ส่วนตัว", systemImage: "lock.fill", color: AppTheme.purple)
                    }
                    if task.remindDate != nil {
                        metaChip(text: "เตือน", systemImage: "bell.fill", color: AppTheme.info)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                if !task.assigneeInitials.isEmpty {
                    Text(task.assigneeInitials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(AppTheme.brand))
                        .accessibilityLabel("มอบหมายให้ \(task.assigneeName ?? "")")
                }
                Text(DashboardAggregations.dayLabel(task.dueDate))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
                pinButton(task)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(alignment: .leading) {
            if task.isFocus {
                Capsule()
                    .fill(AppTheme.purple)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
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

    private func pinButton(_ task: WorkTask) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await store.toggleFocus(task, adminId: adminId) }
        } label: {
            Image(systemName: task.isFocus ? "pin.fill" : "pin")
                .font(.caption)
                .foregroundStyle(task.isFocus ? AppTheme.purple : AppTheme.inkMuted.opacity(0.65))
                .frame(width: 26, height: 22)
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
            Task { await store.advanceStatus(task) }
        } label: {
            Image(systemName: task.status.systemImage)
                .font(.title3)
                .foregroundStyle(task.status.color)
                .frame(width: 30, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title) สถานะ \(task.status.label) แตะเพื่อเปลี่ยนเป็น \(task.status.next.label)")
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

    private var addButton: some View {
        Button {
            let day = segment == .calendar ? selectedDay : today
            let draft = WorkTask.new(ownerAdminId: adminId, ownerName: adminName, dueDate: day)
            editorTarget = EditorTarget(id: draft.id, task: draft, isNew: true)
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [AppTheme.brand, AppTheme.brandMid],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .shadow(color: AppTheme.brand.opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, AppTheme.spaceLG)
        .padding(.bottom, AppTheme.spaceLG)
        .accessibilityLabel("เพิ่มงานใหม่")
    }
}

// MARK: - Segment pill

private struct TasksSegmentPill: View {
    @Binding var selection: TasksSegment
    @Namespace private var pillNS

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TasksSegment.allCases) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { selection = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection == option ? .white : AppTheme.inkMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                if selection == option {
                                    Capsule()
                                        .fill(AppTheme.brand)
                                        .matchedGeometryEffect(id: "tasksSegThumb", in: pillNS)
                                        .shadow(color: AppTheme.brand.opacity(0.35), radius: 6, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
        }
        .background(Capsule().fill(AppTheme.surfaceSoft))
        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
    }
}
