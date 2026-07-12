import SwiftUI

struct RealtimeV4View: View {
    let transactions: [Transaction]
    let employees: [Employee]
    let settings: AppSettings

    @State private var focusDate = Date()
    @State private var lastRefresh = Date()
    @State private var isLive = true

    private var focusDateStr: String { DashboardAggregations.formatYMD(focusDate) }

    private var countData: (vehicles: [CountRecordVehicleRow], sand: [CountRecordSandRow], tripTotal: Int, sandTotal: Int) {
        DashboardAggregations.countRecordRows(for: focusDateStr, transactions: transactions, employees: employees)
    }

    private var financial: FinancialSummary {
        let dayTx = transactions.filter { String($0.date.prefix(10)) == focusDateStr }
        return DashboardAggregations.aggregateFinancial(dayTx)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Real-time (V.4)")
                .font(.title2.bold())

            HStack {
                DatePicker("วันที่", selection: $focusDate, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                liveBadge
            }

            HStack(spacing: 8) {
                statusChip("Live", isLive ? .green : .gray, "bolt.fill")
                statusChip("Synced \(timeString(lastRefresh))", .blue, "arrow.triangle.2.circlepath")
                statusChip("Mobile", .purple, "iphone")
            }
            .font(.caption)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                miniStat("รายรับ", financial.income, .green)
                miniStat("รายจ่าย", financial.expense, .red)
                miniStat("กำไร", financial.profit, financial.profit >= 0 ? .blue : .orange)
            }

            GroupBox("บันทึกและนับจำนวน — \(DashboardAggregations.thaiDateLong(focusDateStr))") {
                HStack(spacing: 16) {
                    VStack {
                        Text("\(countData.tripTotal)").font(.title.bold())
                        Text("เที่ยวรถ").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    VStack {
                        Text("\(countData.sandTotal)").font(.title.bold())
                        Text("ถังทราย").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)

                if countData.vehicles.isEmpty && countData.sand.isEmpty {
                    Text("ยังไม่มีการนับในวันนี้").foregroundStyle(.secondary).font(.caption)
                }

                if !countData.vehicles.isEmpty {
                    Text("จำนวนเที่ยวรถ").font(.subheadline.bold())
                    ForEach(countData.vehicles) { row in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(row.vehicleName).font(.caption.bold())
                                Text("คนขับ: \(row.driverName)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("เช้า \(row.morningTrips) / บ่าย \(row.afternoonTrips)")
                                .font(.caption)
                            if row.isBroken {
                                Image(systemName: "wrench.fill").foregroundStyle(.orange)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                    }
                }

                if !countData.sand.isEmpty {
                    Text("การร่อนทราย").font(.subheadline.bold()).padding(.top, 8)
                    ForEach(countData.sand) { row in
                        HStack {
                            Text("ถัง \(row.drums)")
                            Spacer()
                            Text("เช้า \(row.morningDrums) / บ่าย \(row.afternoonDrums)")
                                .font(.caption)
                            if row.lapCount > 0 {
                                Text("\(row.lapCount) รอบ").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                    }
                }
            }

            Text("แอป: \(settings.appName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            lastRefresh = Date()
            isLive = true
        }
        .onChange(of: transactions.count) { _ in
            lastRefresh = Date()
            isLive = true
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(isLive ? Color.green : Color.gray).frame(width: 8, height: 8)
            Text(isLive ? "Live" : "Offline").font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.green.opacity(0.12)))
    }

    private func statusChip(_ text: String, _ color: Color, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }

    private func miniStat(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(DashboardAggregations.formatNumber(value))
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
