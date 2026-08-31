import SwiftUI

/// Date selection owned by a report screen. Starts on today and can widen to a range.
///
/// Reports keep their own copy of this instead of sharing `AppState.datePreset`, so changing
/// the day here no longer moves the Home tab's filter.
struct ReportDateScope: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case day, range

        var id: String { rawValue }

        var label: String {
            switch self {
            case .day: return "วัน"
            case .range: return "ช่วง"
            }
        }
    }

    /// `fetchTransactions()` only pulls the last 90 days, so anything older is guaranteed empty.
    static let historyWindowDays = 90

    var mode: Mode = .day
    var day: Date
    var preset: DateRangePreset = .days7
    var customStart: Date
    var customEnd: Date

    init(day: Date = Date()) {
        let cal = DashboardAggregations.gregorian
        self.day = day
        self.customStart = cal.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        self.customEnd = Date()
    }

    // MARK: - Derived

    var dayKey: String { DashboardAggregations.formatYMD(day) }

    var filter: DateFilter {
        switch mode {
        case .day:
            return DateFilter(start: dayKey, end: dayKey)
        case .range:
            return DashboardAggregations.dateFilter(
                preset: preset,
                customStart: customStart,
                customEnd: customEnd
            )
        }
    }

    var isSingleDay: Bool { mode == .day }

    var title: String {
        switch mode {
        case .day:
            let today = DashboardAggregations.todayYMD()
            if dayKey == today { return "วันนี้" }
            if dayKey == DashboardAggregations.shiftDateStr(today, deltaDays: -1) { return "เมื่อวาน" }
            return Self.shortThaiDate(day)
        case .range:
            if preset == .custom {
                return "\(Self.shortThaiDate(customStart)) – \(Self.shortThaiDate(customEnd))"
            }
            return preset.label
        }
    }

    var isToday: Bool { dayKey == DashboardAggregations.todayYMD() }

    var canGoForward: Bool { dayKey < DashboardAggregations.todayYMD() }

    var canGoBack: Bool { dayKey > Self.earliestKey }

    static var earliestDate: Date {
        DashboardAggregations.gregorian.date(byAdding: .day, value: -historyWindowDays, to: Date()) ?? Date()
    }

    static var earliestKey: String { DashboardAggregations.formatYMD(earliestDate) }

    // MARK: - Mutations

    mutating func shiftDay(_ delta: Int) {
        let cal = DashboardAggregations.gregorian
        guard let moved = cal.date(byAdding: .day, value: delta, to: day) else { return }
        select(day: moved)
    }

    /// Switches to day mode on `newDay`, clamped to the fetch window.
    mutating func select(day newDay: Date) {
        mode = .day
        let key = DashboardAggregations.formatYMD(newDay)
        if key > DashboardAggregations.todayYMD() {
            day = Date()
        } else if key < Self.earliestKey {
            day = Self.earliestDate
        } else {
            day = newDay
        }
    }

    mutating func selectDayKey(_ key: String) {
        guard let parsed = Self.parseKey(key) else { return }
        select(day: parsed)
    }

    mutating func goToday() {
        select(day: Date())
    }

    mutating func useRange(_ newPreset: DateRangePreset) {
        mode = .range
        preset = newPreset
        if newPreset == .custom {
            normalizeCustomRange()
        }
    }

    /// Switch day/range mode and keep the selected dates coherent.
    mutating func setMode(_ newMode: Mode) {
        switch newMode {
        case .day:
            // Anchor day to the end of the prior range (or today).
            if mode == .range {
                let endKey = filter.end
                if let parsed = Self.parseKey(endKey) {
                    select(day: parsed)
                } else {
                    goToday()
                }
            } else {
                mode = .day
            }
        case .range:
            // Keep current day as the range end; default to 7-day window ending today.
            let anchor = day
            mode = .range
            if preset == .custom {
                customEnd = anchor
                if customStart > customEnd {
                    customStart = DashboardAggregations.gregorian.date(byAdding: .day, value: -6, to: customEnd)
                        ?? customEnd
                }
                normalizeCustomRange()
            } else {
                preset = .days7
            }
        }
    }

    mutating func normalizeCustomRange() {
        if customStart > customEnd {
            swap(&customStart, &customEnd)
        }
        let earliest = Self.earliestDate
        let today = Date()
        if customStart < earliest { customStart = earliest }
        if customEnd > today { customEnd = today }
        if customStart > customEnd { customStart = customEnd }
    }

    // MARK: - Formatting

    static func shortThaiDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .buddhist)
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "EEE d MMM yy"
        return f.string(from: date)
    }

    static func parseKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = DashboardAggregations.gregorian
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(key.prefix(10)))
    }
}

// MARK: - Bar

enum ReportDateBarStyle {
    /// Dark text on a light card — the default for report screens.
    case surface
    /// White text for use on top of a brand gradient.
    case onGradient
}

/// Day stepper plus an optional day/range switch, bound to a `ReportDateScope`.
struct ReportDateBar: View {
    @Binding var scope: ReportDateScope
    var style: ReportDateBarStyle = .surface
    /// Hidden for the daily summary card, which is day-only.
    var showsModeSwitch: Bool = true
    /// When set, day picker uses the fuel activity calendar instead of the system DatePicker.
    var fuelCalendarTransactions: [Transaction]? = nil
    var fuelCalendarRevision: Int = 0

    @State private var showDayPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsModeSwitch {
                modeSwitch
            }
            if scope.mode == .day {
                dayStepper
            } else {
                rangeControls
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Mode switch

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(ReportDateScope.Mode.allCases) { mode in
                let isActive = scope.mode == mode
                Button {
                    withAnimation(.snappy(duration: 0.22)) { scope.setMode(mode) }
                } label: {
                    Text(mode.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isActive ? activeText : mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isActive {
                                Capsule().fill(activeFill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(trackFill))
        .frame(maxWidth: 180)
    }

    // MARK: Day mode

    private var dayStepper: some View {
        HStack(spacing: 8) {
            stepButton(systemImage: "chevron.left", enabled: scope.canGoBack) {
                scope.shiftDay(-1)
            }
            .accessibilityLabel("วันก่อนหน้า")

            Button {
                showDayPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(scope.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(Capsule().fill(trackFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เลือกวันที่ ตอนนี้คือ \(scope.title)")

            stepButton(systemImage: "chevron.right", enabled: scope.canGoForward) {
                scope.shiftDay(1)
            }
            .accessibilityLabel("วันถัดไป")

            if !scope.isToday {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { scope.goToday() }
                } label: {
                    Text("วันนี้")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(activeText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(activeFill))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showDayPicker) {
            if let txs = fuelCalendarTransactions {
                FuelFocusCalendarSheet(
                    selection: Binding(
                        get: { scope.day },
                        set: { scope.select(day: $0) }
                    ),
                    transactions: txs,
                    transactionsRevision: fuelCalendarRevision,
                    onDismiss: { showDayPicker = false }
                )
            } else {
                dayPickerSheet
            }
        }
    }

    private var dayPickerSheet: some View {
        NavigationStack {
            ScrollView {
                DatePicker(
                    "เลือกวันที่",
                    selection: Binding(
                        get: { scope.day },
                        set: { scope.select(day: $0) }
                    ),
                    in: ReportDateScope.earliestDate...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "th_TH"))
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationTitle("เลือกวันที่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ") { showDayPicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large, .fraction(0.92)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? primaryText : mutedText.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(Circle().fill(trackFill))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Range mode

    private var rangeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(DateRangePreset.allCases) { item in
                    Button {
                        scope.preset = item
                    } label: {
                        if scope.preset == item {
                            Label(item.label, systemImage: "checkmark")
                        } else {
                            Text(item.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(scope.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(trackFill))
            }

            if scope.preset == .custom {
                HStack(spacing: 8) {
                    DatePicker(
                        "เริ่ม",
                        selection: Binding(
                            get: { scope.customStart },
                            set: { newValue in
                                scope.customStart = newValue
                                scope.normalizeCustomRange()
                            }
                        ),
                        in: ReportDateScope.earliestDate...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    Text("–").foregroundStyle(mutedText)
                    DatePicker(
                        "สิ้นสุด",
                        selection: Binding(
                            get: { scope.customEnd },
                            set: { newValue in
                                scope.customEnd = newValue
                                scope.normalizeCustomRange()
                            }
                        ),
                        in: ReportDateScope.earliestDate...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    Spacer(minLength: 0)
                }
                .environment(\.locale, Locale(identifier: "th_TH"))
                .font(.subheadline)
            }
        }
    }

    // MARK: Palette

    private var primaryText: Color {
        style == .onGradient ? .white : AppTheme.ink
    }

    private var mutedText: Color {
        style == .onGradient ? .white.opacity(0.7) : AppTheme.inkMuted
    }

    private var activeText: Color {
        style == .onGradient ? AppTheme.brandDark : .white
    }

    private var activeFill: Color {
        style == .onGradient ? .white : AppTheme.brand
    }

    private var trackFill: Color {
        style == .onGradient ? .white.opacity(0.16) : AppTheme.surfaceSoft
    }
}
