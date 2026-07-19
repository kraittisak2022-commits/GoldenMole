import SwiftUI

struct CalendarV3View: View {
    let transactions: [Transaction]
    let employees: [Employee]

    @State private var visibleMonth: Date = Date()
    @State private var selectedDay: String?

    private var monthDates: [Date?] {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: visibleMonth)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: first) { cells.append(d) }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var holidays: [String: String] {
        let year = DashboardAggregations.gregorian.component(.year, from: visibleMonth)
        return DashboardAggregations.thaiPublicHolidayMap(year: year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
            SectionHeader(
                title: "ปฏิทิน (V.3)",
                systemImage: "calendar",
                subtitle: "รายรับ รายจ่าย และวันหยุด"
            )

            SectionCard {
                HStack {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.brand)
                    }
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.brand)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(["จ", "อ", "พ", "พฤ", "ศ", "ส", "อา"], id: \.self) { d in
                        Text(d)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                        if let date {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 64)
                        }
                    }
                }
            }

            if let selectedDay {
                dayDetailPanel(selectedDay)
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .buddhist)
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: visibleMonth)
    }

    private func shiftMonth(_ delta: Int) {
        visibleMonth = DashboardAggregations.gregorian.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
        selectedDay = nil
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DashboardAggregations.formatYMD(date)
        let dayTx = transactions.filter { String($0.date.prefix(10)) == key }
        let income = dayTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = dayTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let holiday = holidays[key]
        let laborCount = dayTx.filter { $0.category == "Labor" && $0.laborStatus == "Work" }.count
        let isSelected = selectedDay == key
        let isToday = key == DashboardAggregations.formatYMD(Date())

        return Button {
            selectedDay = key
        } label: {
            VStack(spacing: 4) {
                Text("\(DashboardAggregations.gregorian.component(.day, from: date))")
                    .font(.subheadline.weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? AppTheme.brand : .primary)
                HStack(spacing: 3) {
                    if income > 0 {
                        Circle().fill(AppTheme.income).frame(width: 5, height: 5)
                    }
                    if expense > 0 {
                        Circle().fill(AppTheme.expense).frame(width: 5, height: 5)
                    }
                    if holiday != nil {
                        Circle().fill(AppTheme.warning).frame(width: 5, height: 5)
                    }
                    if laborCount > 0 {
                        Circle().fill(AppTheme.info).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppTheme.brand.opacity(0.14) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isToday ? AppTheme.brand.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func dayDetailPanel(_ date: String) -> some View {
        let dayTx = transactions.filter { String($0.date.prefix(10)) == date }
        let income = dayTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = dayTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let calendarEntries = dayTx.filter { $0.category == "Calendar" }
        let labor = dayTx.filter { $0.category == "Labor" }
        let logs = dayTx.filter { $0.category == "DailyLog" }

        return SectionCard(
            "รายละเอียด \(DashboardAggregations.thaiDateLong(date))",
            systemImage: "doc.text.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("รายรับ").foregroundStyle(.secondary)
                    Spacer()
                    Text(DashboardAggregations.formatCurrency(income)).foregroundStyle(AppTheme.income).bold()
                }
                HStack {
                    Text("รายจ่าย").foregroundStyle(.secondary)
                    Spacer()
                    Text(DashboardAggregations.formatCurrency(expense)).foregroundStyle(AppTheme.expense).bold()
                }
                if let h = holidays[date] {
                    Label(h, systemImage: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }
                if !labor.isEmpty {
                    Label("ค่าแรง \(labor.count) รายการ", systemImage: "person.2.fill")
                        .font(.caption)
                }
                if !logs.isEmpty {
                    Label("บันทึกงาน \(logs.count) รายการ", systemImage: "list.clipboard")
                        .font(.caption)
                }
                ForEach(calendarEntries) { e in
                    Text("• \(e.description) (\(e.eventType ?? e.subCategory ?? ""))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
