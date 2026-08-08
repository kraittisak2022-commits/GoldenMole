import SwiftUI

/// Daily ops modules mirrored from the Android field menus.
enum OpsMenuItem: String, CaseIterable, Identifiable, Hashable {
    case countRecord
    case attendance
    case drumTrips
    case macro
    case fuel
    case events
    case leave
    case advance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countRecord: return "บันทึกและนับจำนวน"
        case .attendance: return "เช็คชื่อ"
        case .drumTrips: return "บันทึกรถดรัมและจำนวนเที่ยว"
        case .macro: return "การใช้รถแม็คโคร"
        case .fuel: return "น้ำมัน"
        case .events: return "เหตุการณ์"
        case .leave: return "ลางาน"
        case .advance: return "เบิกเงิน"
        }
    }

    var systemImage: String {
        switch self {
        case .countRecord: return "plusminus.circle.fill"
        case .attendance: return "person.crop.circle.badge.checkmark"
        case .drumTrips: return "truck.box.fill"
        case .macro: return "gearshape.2.fill"
        case .fuel: return "fuelpump.fill"
        case .events: return "exclamationmark.bubble.fill"
        case .leave: return "calendar.badge.minus"
        case .advance: return "banknote.fill"
        }
    }

    var accent: Color {
        switch self {
        case .countRecord: return AppTheme.info
        case .attendance: return AppTheme.labor
        case .drumTrips: return AppTheme.vehicle
        case .macro: return AppTheme.warning
        case .fuel: return AppTheme.fuel
        case .events: return AppTheme.purple
        case .leave: return AppTheme.slate
        case .advance: return AppTheme.income
        }
    }

    /// When set, selecting the item switches the main tab instead of opening a sheet.
    var switchesToTab: AppMainTab? {
        nil
    }
}

// MARK: - Overlay + drawer

struct OpsSideMenuOverlay: View {
    @Binding var isPresented: Bool
    @Binding var dragOffset: CGFloat
    let onSelect: (OpsMenuItem) -> Void

    private let drawerRatio: CGFloat = 0.78
    private let edgeSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * drawerRatio
            let closedX = width
            let openProgress = max(0, min(1, 1 - (dragOffset / width)))

            ZStack(alignment: .trailing) {
                Color.black
                    .opacity(0.42 * Double(openProgress))
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .allowsHitTesting(isPresented || dragOffset < width - 2)

                HStack(spacing: 0) {
                    // Drag handle strip
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 4, height: 44)
                        .padding(.leading, 8)
                        .padding(.trailing, 4)

                    OpsSideMenuPanel(onSelect: { item in
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            onSelect(item)
                        }
                    }, onClose: close)
                }
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.surface)
                        .shadow(color: .black.opacity(0.28), radius: 24, x: -8, y: 0)
                )
                .offset(x: isPresented ? dragOffset : closedX)
                .gesture(panelDrag(width: width))
            }
        }
        .transition(.opacity)
    }

    private func close() {
        withAnimation(edgeSpring) {
            isPresented = false
            dragOffset = 0
        }
    }

    private func panelDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dx = max(0, value.translation.width)
                dragOffset = dx
            }
            .onEnded { value in
                let shouldClose = value.translation.width > width * 0.28
                    || value.predictedEndTranslation.width > width * 0.45
                withAnimation(edgeSpring) {
                    if shouldClose {
                        isPresented = false
                        dragOffset = 0
                    } else {
                        dragOffset = 0
                    }
                }
            }
    }
}

struct OpsSideMenuPanel: View {
    @Environment(AppState.self) private var appState
    let onSelect: (OpsMenuItem) -> Void
    let onClose: () -> Void

    private var countRecordStatus: String? {
        CountRecordLogic.menuStatusLabel(
            dayKey: DashboardAggregations.todayYMD(),
            transactions: appState.transactions,
            employees: appState.employees
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("เมนูงานประจำวัน")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("ปัดจากขอบขวาเพื่อเปิดเมนูนี้")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppTheme.surfaceSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิดเมนู")
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(OpsMenuItem.allCases.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(item.accent)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(item.accent.opacity(0.14))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                        .multilineTextAlignment(.leading)
                                    if item == .countRecord, let status = countRecordStatus {
                                        Text(status)
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.inkMuted)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < OpsMenuItem.allCases.count - 1 {
                            Rectangle()
                                .fill(AppTheme.hairline)
                                .frame(height: 1)
                                .padding(.leading, 70)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.surfaceSoft.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppTheme.hairline, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Destinations

struct OpsMenuDestinationView: View {
    let item: OpsMenuItem

    var body: some View {
        switch item {
        case .countRecord:
            CountRecordHubView()
        case .attendance:
            AttendanceHubView()
        case .drumTrips:
            DrumTripHubView()
        case .macro:
            MacroVehicleHubView()
        case .fuel:
            CategoryReportScreen(type: .fuel)
        case .events:
            OpsFilteredRecordListView(
                title: "เหตุการณ์",
                emptyMessage: "ยังไม่มีเหตุการณ์ / นัดหมายวันนี้",
                predicate: { t in
                    t.category == "Calendar"
                        || t.subCategory == "Reminder"
                        || t.subCategory == "Holiday"
                        || t.subCategory == "Appointment"
                        || (t.category == "DailyLog" && (t.subCategory ?? "").localizedCaseInsensitiveContains("event"))
                }
            )
        case .leave:
            OpsFilteredRecordListView(
                title: "ลางาน",
                emptyMessage: "ยังไม่มีบันทึกลางาน",
                predicate: { t in
                    t.type == .leave
                        || t.category == "Leave"
                        || CalendarV3Logic.isLaborLeaveRecord(t)
                }
            )
        case .advance:
            OpsFilteredRecordListView(
                title: "เบิกเงิน",
                emptyMessage: "ยังไม่มีรายการเบิกเงิน",
                predicate: { t in
                    let status = (t.laborStatus ?? "").lowercased()
                    return status == "advance"
                        || (t.advanceAmount ?? 0) > 0
                        || t.subCategory == "Advance"
                }
            )
        }
    }
}

struct OpsAttendanceDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var snapshot = TodayOpsSnapshot.empty

    private var dayKey: String { DashboardAggregations.todayYMD() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    attendanceChip(count: snapshot.presentCount, title: "มาทำงาน", color: AppTheme.income)
                    attendanceChip(count: snapshot.leaveCount, title: "ลา", color: AppTheme.warning)
                    attendanceChip(count: snapshot.absentCount, title: "ขาด", color: AppTheme.expense)
                }

                Text("นับเฉพาะพนักงานท่าทรายและคนขับรถแม็คโคร")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)

                if snapshot.staffRows.isEmpty {
                    EmptyStateView(
                        title: "ยังไม่มีข้อมูลเช็คชื่อ",
                        message: "เมื่อมีบันทึกวันนี้ รายชื่อจะแสดงที่นี่",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    staffSection(title: "มาทำงาน", rows: snapshot.staffRows.filter { $0.status == .work }, color: AppTheme.income)
                    staffSection(title: "ลา", rows: snapshot.staffRows.filter { $0.status == .leave }, color: AppTheme.warning)
                    staffSection(title: "ขาด", rows: snapshot.staffRows.filter { $0.status == .absent }, color: AppTheme.expense)
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .background(DashboardBackground())
        .navigationTitle("เช็คชื่อ")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(dayKey)-\(appState.transactionsRevision)") {
            let txs = appState.transactions
            let emps = appState.employees
            let settings = appState.settings
            let key = dayKey
            snapshot = await Task.detached(priority: .userInitiated) {
                TodayOpsSnapshot.build(
                    transactions: txs,
                    employees: emps,
                    settings: settings,
                    dayKey: key
                )
            }.value
        }
    }

    private func attendanceChip(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.black))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func staffSection(title: String, rows: [TodayOpsSnapshot.StaffRow], color: Color) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) · \(rows.count)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(color)

                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            if !row.workLabels.isEmpty {
                                Text(row.workLabels.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                        }
                        Spacer()
                        if row.wage > 0 {
                            Text(DashboardAggregations.formatCurrency(row.wage))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.inkSecondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.surfaceSoft)
                    )
                }
            }
        }
    }
}

struct OpsMacroVehicleReportView: View {
    @Environment(AppState.self) private var appState
    @State private var scope = ReportDateScope()

    private var scoped: [Transaction] {
        DashboardAggregations.filterByRange(appState.transactions, range: scope.filter)
            .filter {
                CategoryReportType.vehicle.matches($0)
                    && CountRecordLogic.isMacroVehicleId($0.vehicleId)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            ReportDateBar(scope: $scope)
                .padding(.horizontal, AppTheme.spaceLG)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceSoft.opacity(0.85))

            ScrollView {
                if scoped.isEmpty {
                    EmptyStateView(
                        title: "ยังไม่มีบันทึกแม็คโคร",
                        message: "เมื่อมีการใช้รถแม็คโครใน\(scope.title) จะแสดงที่นี่",
                        systemImage: "gearshape.2"
                    )
                    .padding(AppTheme.spaceLG)
                } else {
                    CategoryReportView(
                        type: .vehicle,
                        transactions: scoped,
                        settings: appState.settings,
                        employees: appState.employees,
                        dateFilter: scope.filter,
                        scopeTitle: scope.title
                    )
                    .padding(AppTheme.spaceLG)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(DashboardBackground())
        .navigationTitle("การใช้รถแม็คโคร")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OpsFilteredRecordListView: View {
    let title: String
    let emptyMessage: String
    let predicate: (Transaction) -> Bool

    @Environment(AppState.self) private var appState

    private var filtered: [Transaction] {
        appState.transactions
            .filter(predicate)
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                EmptyStateView(
                    title: "ไม่พบ\(title)",
                    message: emptyMessage,
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                RecordListView(transactions: filtered, navigationTitleText: title)
            }
        }
    }
}
