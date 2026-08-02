import SwiftUI

/// Top-of-Reports card that audits the four Android daily menus for a chosen day.
///
/// Replaces the older Daily Wizard 7-step recap so the board matches what field
/// staff actually fill on the phone: count-record, attendance, macro excavator, fuel.
struct MobileDailyAuditCard: View {
    let transactions: [Transaction]
    let employees: [Employee]

    @State private var scope = ReportDateScope()
    @State private var summary = MobileDailyAuditDay.empty(dayKey: "")

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var suggestedDay: String? {
        let latest = MobileDailyAuditSnapshot.latestDayWithRecords(
            in: transactions,
            onOrBefore: DashboardAggregations.todayYMD()
        )
        guard let latest, latest != scope.dayKey else { return nil }
        return latest
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 16, y: 6)
        .task(id: rebuildKey) { await rebuild() }
    }

    private var rebuildKey: String {
        "\(scope.dayKey)|\(transactions.count)|\(employees.count)"
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 140, height: 140)
                .blur(radius: 26)
                .offset(x: 200, y: -46)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MOBILE CHECK")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("ตรวจบันทึกรายวัน")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(DashboardAggregations.thaiDateLong(scope.dayKey))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                    completionRing
                }

                ReportDateBar(scope: $scope, style: .onGradient, showsModeSwitch: false)
            }
            .padding(18)
        }
    }

    private var completionRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(summary.completion))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(summary.completedCount)")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                Text("/\(summary.itemCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 54, height: 54)
        .animation(.snappy(duration: 0.3), value: summary.completion)
        .accessibilityLabel("ครบแล้ว \(summary.completedCount) จาก \(summary.itemCount) เมนู")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            if summary.isEmpty {
                emptyState
            } else {
                if !summary.missingTitles.isEmpty {
                    missingBanner
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(summary.items) { item in
                        moduleTile(item)
                    }
                }
            }
        }
        .padding(AppTheme.spaceLG)
    }

    private var missingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.warning)
            Text(bannerText)
                .font(.caption)
                .foregroundStyle(AppTheme.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .fill(AppTheme.warning.opacity(0.12))
        )
    }

    private var bannerText: String {
        let incomplete = summary.items.filter { $0.status == .incomplete }.map(\.kind.title)
        let pending = summary.items.filter { $0.status == .pending }.map(\.kind.title)
        var parts: [String] = []
        if !incomplete.isEmpty {
            parts.append("กรอกไม่ครบ \(incomplete.joined(separator: " · "))")
        }
        if !pending.isEmpty {
            parts.append("ยังไม่กรอก \(pending.joined(separator: " · "))")
        }
        return parts.joined(separator: " — ")
    }

    private func moduleTile(_ item: MobileDailyAuditItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.kind.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [item.kind.accent, item.kind.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(item.kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: item.status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.status.color)
            }

            Text(item.status.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(item.status.color)

            Text(item.headline)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(item.status == .pending ? AppTheme.inkMuted : AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(
                    item.status == .incomplete
                        ? AppTheme.warning.opacity(0.45)
                        : AppTheme.hairline,
                    lineWidth: 1
                )
        )
        .opacity(item.status == .pending ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.title) \(item.status.label) \(item.headline)")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmptyStateView(
                title: "ยังไม่มีการบันทึกใน\(scope.title)",
                message: "ยังไม่มีข้อมูลจากเมนูมือถือทั้งสี่รายการ — บันทึกและนับจำนวน · เช็คชื่อ · แม็คโคร · น้ำมัน",
                systemImage: "iphone.and.arrow.forward"
            )

            if let suggested = suggestedDay {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        scope.selectDayKey(suggested)
                    }
                } label: {
                    Label(
                        "ดูวันล่าสุดที่มีข้อมูล (\(DashboardAggregations.thaiDateLong(suggested)))",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
            }
        }
    }

    // MARK: - Build

    private func rebuild() async {
        let key = scope.dayKey
        let txs = transactions
        let emps = employees

        let built = await Task.detached(priority: .userInitiated) {
            MobileDailyAuditSnapshot.build(dayKey: key, transactions: txs, employees: emps)
        }.value

        guard !Task.isCancelled else { return }
        summary = built
    }
}
