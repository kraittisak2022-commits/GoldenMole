import SwiftUI

struct CalendarV3View: View {
    let transactions: [Transaction]
    let employees: [Employee]

    @State private var visibleMonth: Date = Date()
    @State private var selectedDay: String?

    private var monthDates: [Date?] {
        let cal = Calendar.current
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
        let year = Calendar.current.component(.year, from: visibleMonth)
        return DashboardAggregations.thaiPublicHolidayMap(year: year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ปฏิทิน (V.3)")
                .font(.title2.bold())

            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["จ", "อ", "พ", "พฤ", "ศ", "ส", "อา"], id: \.self) { d in
                    Text(d).font(.caption.bold()).foregroundStyle(.secondary)
                }
                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 56)
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
        f.locale = Locale(identifier: "th_TH")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: visibleMonth)
    }

    private func shiftMonth(_ delta: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
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

        return Button {
            selectedDay = key
        } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.bold())
                if income > 0 {
                    Text("+\(Int(income))").font(.system(size: 8)).foregroundStyle(.green)
                }
                if expense > 0 {
                    Text("-\(Int(expense))").font(.system(size: 8)).foregroundStyle(.red)
                }
                if let holiday {
                    Text("🎌").font(.system(size: 8))
                    Text(holiday).font(.system(size: 7)).lineLimit(1)
                }
                if laborCount > 0 {
                    Text("👷\(laborCount)").font(.system(size: 8))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
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

        return GroupBox("รายละเอียด \(DashboardAggregations.thaiDateLong(date))") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("รายรับ").foregroundStyle(.secondary)
                    Spacer()
                    Text(DashboardAggregations.formatCurrency(income)).foregroundStyle(.green)
                }
                HStack {
                    Text("รายจ่าย").foregroundStyle(.secondary)
                    Spacer()
                    Text(DashboardAggregations.formatCurrency(expense)).foregroundStyle(.red)
                }
                if let h = holidays[date] {
                    Label(h, systemImage: "flag.fill").font(.caption)
                }
                if !labor.isEmpty {
                    Text("ค่าแรง \(labor.count) รายการ").font(.caption)
                }
                if !logs.isEmpty {
                    Text("บันทึกงาน \(logs.count) รายการ").font(.caption)
                }
                ForEach(calendarEntries) { e in
                    Text("• \(e.description) (\(e.eventType ?? e.subCategory ?? ""))").font(.caption)
                }
            }
        }
    }
}
