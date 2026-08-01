import SwiftUI

/// Daily recap of the seven Daily Wizard steps, shown at the top of the Reports tab.
///
/// Mirrors the wizard's own "ตรวจสอบ" step: a tile per step, and the ones with no rows are
/// called out so a half-finished day is obvious at a glance.
struct DailyWizardSummaryCard: View {
    let transactions: [Transaction]
    let employees: [Employee]

    @State private var scope = ReportDateScope()
    @State private var summary = DailyWizardDay.empty(dayKey: "")

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    /// Newest recorded day that isn't the one already on screen.
    private var suggestedDay: String? {
        let latest = DailyWizardSnapshot.latestDayWithRecords(
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
                        Text("DAILY WIZARD")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("สรุปงานประจำวัน")
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
                Text("/\(summary.stepCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 54, height: 54)
        .animation(.snappy(duration: 0.3), value: summary.completion)
        .accessibilityLabel("บันทึกแล้ว \(summary.completedCount) จาก \(summary.stepCount) ขั้นตอน")
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
                    ForEach(summary.steps) { step in
                        stepTile(step)
                    }
                }

                moneyFooter
            }
        }
        .padding(AppTheme.spaceLG)
    }

    private var missingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.warning)
            Text("ยังไม่บันทึก \(summary.missingTitles.joined(separator: " · "))")
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

    private func stepTile(_ step: DailyWizardStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: step.kind.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [step.kind.accent, step.kind.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(step.kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if step.isRecorded {
                    Text("\(step.recordCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(step.kind.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(step.kind.accent.opacity(0.14)))
                }
            }

            if step.isRecorded {
                Text(step.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(1)
                }
            } else {
                Text("ยังไม่บันทึก")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
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
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .opacity(step.isRecorded ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            step.isRecorded
                ? "\(step.kind.title) \(step.headline) \(step.detail ?? "")"
                : "\(step.kind.title) ยังไม่บันทึก"
        )
    }

    private var moneyFooter: some View {
        HStack(spacing: 10) {
            moneyPill(
                title: "รายจ่ายรวม",
                value: DashboardAggregations.formatCurrency(summary.totalSpend),
                color: AppTheme.expense
            )
            moneyPill(
                title: "รายรับ",
                value: DashboardAggregations.formatCurrency(summary.totalIncome),
                color: AppTheme.income
            )
        }
    }

    private func moneyPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmptyStateView(
                title: "ยังไม่มีการบันทึกใน\(scope.title)",
                message: "วันนี้ยังไม่มีข้อมูลจาก Daily Wizard",
                systemImage: "square.and.pencil"
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
            DailyWizardSnapshot.build(dayKey: key, transactions: txs, employees: emps)
        }.value

        guard !Task.isCancelled else { return }
        summary = built
    }
}
