import SwiftUI

/// Analytics tab landing — pick combined / trip / sand analysis.
struct OpsTrendAnalyticsMenuView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ศูนย์วิเคราะห์ข้อมูล")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("เลือกว่าจะดูวันนี้ / รายสัปดาห์ / รายเดือนแบบรวม หรือแยกเที่ยวรถกับร่อนทราย")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                VStack(spacing: 12) {
                    menuLink(
                        focus: .trip,
                        title: "วิเคราะห์เที่ยวรถ",
                        subtitle: "วันนี้ · สัปดาห์ · เดือน · แตะดูรายละเอียด",
                        systemImage: "truck.box.fill",
                        accent: AppTheme.info
                    )
                    menuLink(
                        focus: .sand,
                        title: "วิเคราะห์ร่อนทราย",
                        subtitle: "วันนี้ · สัปดาห์ · เดือน · แตะดูรายละเอียด",
                        systemImage: "drop.fill",
                        accent: AppTheme.brand
                    )
                    menuLink(
                        focus: .both,
                        title: "วิเคราะห์รวม",
                        subtitle: "วันนี้ · สัปดาห์ · เดือน · กำหนดช่วงเองได้",
                        systemImage: "chart.xyaxis.line",
                        accent: Color(hex: "#16a34a")
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(DashboardBackground())
        .navigationTitle("วิเคราะห์")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func menuLink(
        focus: OpsTrendFocus,
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        NavigationLink {
            OpsTrendAnalyticsHubView(focus: focus)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .fill(AppTheme.surface)
                    .shadow(color: AppTheme.cardShadow, radius: 16, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("เปิด\(title)")
    }
}
