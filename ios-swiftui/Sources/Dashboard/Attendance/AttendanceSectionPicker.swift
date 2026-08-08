import SwiftUI

struct AttendanceSectionPicker: View {
    let sandSummary: String
    let driverSummary: String
    let onSelect: (AttendanceSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("จะเช็คชื่อกลุ่มไหน?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("เลือกกลุ่มแล้วจัดรายชื่อลงกล่อง ทำงาน / ลา")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .padding(.top, 8)

                sectionCard(
                    section: .sandYard,
                    summary: sandSummary,
                    systemImage: "person.3.fill",
                    accent: Color(red: 0.184, green: 0.714, blue: 0.651)
                )
                sectionCard(
                    section: .driver,
                    summary: driverSummary,
                    systemImage: "truck.box.fill",
                    accent: Color(red: 0.937, green: 0.424, blue: 0)
                )
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
    }

    private func sectionCard(
        section: AttendanceSection,
        summary: String,
        systemImage: String,
        accent: Color
    ) -> some View {
        Button {
            onSelect(section)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
