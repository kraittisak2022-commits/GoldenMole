import SwiftUI

struct RecordListView: View {
    let transactions: [Transaction]
    var navigationTitleText: String = "รายการบันทึก"

    @State private var query = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var categoryFilter: String = "ทั้งหมด"

    private enum TypeFilter: String, CaseIterable, Identifiable {
        case all = "ทั้งหมด"
        case income = "รายรับ"
        case expense = "รายจ่าย"
        case leave = "ลา"

        var id: String { rawValue }
    }

    private var categories: [String] {
        let set = Set(transactions.map(\.category).filter { !$0.isEmpty })
        return ["ทั้งหมด"] + set.sorted()
    }

    private var filtered: [Transaction] {
        transactions.filter { tx in
            switch typeFilter {
            case .all: break
            case .income: if tx.type != .income { return false }
            case .expense: if tx.type != .expense { return false }
            case .leave: if tx.type != .leave { return false }
            }
            if categoryFilter != "ทั้งหมด", tx.category != categoryFilter {
                return false
            }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            let hay = [
                tx.description,
                tx.category,
                tx.subCategory ?? "",
                String(tx.date.prefix(10))
            ].joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            if filtered.isEmpty {
                EmptyStateView(
                    title: "ไม่พบบันทึก",
                    message: "ลองเปลี่ยนคำค้นหาหรือตัวกรอง",
                    systemImage: "doc.text.magnifyingglass"
                )
                Spacer()
            } else {
                List(filtered.prefix(300)) { tx in
                    recordRow(tx)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ค้นหาวันที่ หมวด หรือรายละเอียด", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TypeFilter.allCases) { filter in
                        filterChip(
                            title: filter.rawValue,
                            selected: typeFilter == filter
                        ) {
                            typeFilter = filter
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        filterChip(
                            title: cat,
                            selected: categoryFilter == cat
                        ) {
                            categoryFilter = cat
                        }
                    }
                }
            }

            Text("แสดง \(min(filtered.count, 300)) จาก \(filtered.count) รายการ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.spaceLG)
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? AppTheme.brand : Color(.systemBackground))
                )
                .foregroundStyle(selected ? .white : .primary)
                .overlay(
                    Capsule().stroke(selected ? AppTheme.brand : Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func recordRow(_ tx: Transaction) -> some View {
        let amountColor: Color = {
            switch tx.type {
            case .income: return AppTheme.income
            case .expense: return AppTheme.expense
            case .leave: return AppTheme.slate
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(tx.date.prefix(10)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PillBadge(text: tx.category, color: AppTheme.categoryColor(for: tx.category))
            }
            Text(tx.description.isEmpty ? (tx.subCategory ?? "—") : tx.description)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack {
                if let sub = tx.subCategory, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(DashboardAggregations.formatCurrency(tx.amount))
                    .font(.subheadline.bold())
                    .foregroundStyle(amountColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}
