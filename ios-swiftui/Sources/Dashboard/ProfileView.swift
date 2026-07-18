import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appState: AppState

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spaceLG) {
                profileCard
                orgCard
                actionsCard
                aboutCard
            }
            .padding(AppTheme.spaceLG)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("โปรไฟล์")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await appState.refresh() }
    }

    private var profileCard: some View {
        SectionCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.brand, AppTheme.brandMid],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Text(initials)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(auth.currentAdmin?.displayName ?? "—")
                        .font(.title3.bold())
                    if let username = auth.currentAdmin?.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        PillBadge(text: auth.currentAdmin?.role.rawValue ?? "Admin", color: AppTheme.brand)
                        if let last = auth.currentAdmin?.lastLogin, !last.isEmpty {
                            Text("เข้าล่าสุด \(String(last.prefix(16)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var orgCard: some View {
        SectionCard("องค์กร", systemImage: "building.2.fill", subtitle: "ข้อมูลจากระบบ") {
            row(icon: "app.badge.fill", title: "ชื่อแอป", value: appState.settings.appName)
            if let sub = appState.settings.appSubtext, !sub.isEmpty {
                Divider()
                row(icon: "text.quote", title: "คำโปรย", value: sub)
            }
            Divider()
            row(icon: "car.fill", title: "จำนวนรถ", value: "\(appState.settings.cars.count) คัน")
            Divider()
            row(icon: "person.3.fill", title: "พนักงาน", value: "\(appState.employees.count) คน")
        }
    }

    private var actionsCard: some View {
        SectionCard("การทำงาน", systemImage: "gearshape.fill") {
            Button {
                Task { await appState.refresh() }
            } label: {
                HStack {
                    Label(
                        appState.isLoading ? "กำลังโหลด…" : "รีเฟรชข้อมูล",
                        systemImage: "arrow.clockwise"
                    )
                    Spacer()
                    if appState.isLoading {
                        ProgressView()
                    }
                }
                .foregroundStyle(AppTheme.brand)
            }
            .disabled(appState.isLoading)

            Divider()

            if let url = URL(string: "https://goldenmole.vercel.app/privacy-policy.html") {
                Link(destination: url) {
                    HStack {
                        Label("นโยบายความเป็นส่วนตัว", systemImage: "hand.raised.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var aboutCard: some View {
        SectionCard("เกี่ยวกับ", systemImage: "info.circle.fill") {
            row(icon: "iphone", title: "เวอร์ชัน", value: appVersion)
            Divider()
            Button(role: .destructive) {
                auth.logout()
            } label: {
                Label("ออกจากระบบ", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private var initials: String {
        let name = auth.currentAdmin?.displayName ?? auth.currentAdmin?.username ?? "?"
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        if parts.isEmpty { return "?" }
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
