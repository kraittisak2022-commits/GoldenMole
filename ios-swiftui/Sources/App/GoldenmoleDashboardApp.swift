import SwiftUI

@main
struct GoldenmoleDashboardApp: App {
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bootstrap)
                .environmentObject(bootstrap.appState)
                .task { await bootstrap.start() }
        }
    }
}

@MainActor
final class AppBootstrap: ObservableObject {
    @Published var appState = AppState()
    @Published var authService: AuthService?
    @Published var configError: String?

    func start() async {
        guard SupabaseConfig.isConfigured else {
            configError = "ตั้งค่า SUPABASE_URL และ SUPABASE_ANON_KEY ใน Config/Secrets.xcconfig"
            return
        }
        do {
            let service = try SupabaseService()
            let auth = AuthService(dataService: service)
            authService = auth
            appState.configure(dataService: service)
            await auth.restoreSession()
            if auth.currentAdmin != nil {
                await appState.loadInitial()
            }
        } catch {
            configError = error.localizedDescription
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var bootstrap: AppBootstrap

    var body: some View {
        Group {
            if let configError = bootstrap.configError {
                ConfigErrorView(message: configError)
            } else if let auth = bootstrap.authService {
                // Observe AuthService so login/logout rebuilds this tree.
                AuthGateView(auth: auth)
                    .environmentObject(auth)
                    .environmentObject(bootstrap.appState)
            } else {
                ProgressView("กำลังเริ่มต้น…")
            }
        }
    }
}

/// Holds `@ObservedObject` on AuthService so `currentAdmin` changes trigger navigation.
private struct AuthGateView: View {
    @ObservedObject var auth: AuthService

    var body: some View {
        Group {
            if auth.currentAdmin != nil {
                DashboardShell()
            } else {
                LoginView()
            }
        }
    }
}

private struct ConfigErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("ตั้งค่าไม่ครบ")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
