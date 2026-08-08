import SwiftUI

struct CountRecordWorkModePicker: View {
    let onSelect: (CountRecordWorkMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("เลือกประเภทงาน")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("บันทึกและนับจำนวนสำหรับวันนี้")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .padding(.top, 8)

                ForEach(CountRecordWorkMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(hex: mode.accentHex).opacity(0.14))
                                    .frame(width: 52, height: 52)
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color(hex: mode.accentHex))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(mode.subtitle)
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
                                .strokeBorder(Color(hex: mode.accentHex).opacity(0.35), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
    }
}
