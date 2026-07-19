import SwiftUI
import Observation

@main
struct GoldenmoleDashboardApp: App {
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bootstrap)
                .environment(bootstrap.appState)
                .task { await bootstrap.start() }
        }
    }
}

@MainActor
@Observable
final class AppBootstrap {
    var appState = AppState()
    var authService: AuthService?
    var configError: String?
    /// Becomes true once bootstrap finishes (success or config error).
    var isReady = false

    func start() async {
        defer { isReady = true }

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
    @Environment(AppBootstrap.self) private var bootstrap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    @State private var showSplash = true
    @State private var minDurationElapsed = false

    private var canDismissSplash: Bool {
        bootstrap.isReady && minDurationElapsed
    }

    private var resolvedScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceMode)?.colorScheme
    }

    var body: some View {
        ZStack {
            if showSplash {
                LaunchSplashView()
                    .transition(splashExitTransition)
                    .zIndex(2)
            } else if let configError = bootstrap.configError {
                ConfigErrorView(message: configError)
                    .transition(contentEnterTransition)
            } else if let auth = bootstrap.authService {
                AuthGateView(auth: auth)
                    .environment(auth)
                    .environment(bootstrap.appState)
                    .transition(contentEnterTransition)
            }
        }
        .preferredColorScheme(resolvedScheme)
        .animation(gateAnimation, value: showSplash)
        .task {
            let nanos: UInt64 = reduceMotion ? 400_000_000 : 1_400_000_000
            try? await Task.sleep(nanoseconds: nanos)
            minDurationElapsed = true
            dismissSplashIfReady()
        }
        .onChange(of: bootstrap.isReady) { _, ready in
            if ready {
                dismissSplashIfReady()
            }
        }
    }

    private func dismissSplashIfReady() {
        guard canDismissSplash, showSplash else { return }
        withAnimation(gateAnimation) {
            showSplash = false
        }
    }

    private var gateAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.2)
        }
        return .spring(response: 0.55, dampingFraction: 0.88)
    }

    private var splashExitTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .scale(scale: 1.04))
        )
    }

    private var contentEnterTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.98))
    }
}

/// Observes `AuthService.currentAdmin` (via the Observation framework) to trigger navigation.
private struct AuthGateView: View {
    let auth: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if auth.currentAdmin != nil {
                DashboardShell()
                    .transition(gateTransition)
            } else {
                LoginView()
                    .transition(gateTransition)
            }
        }
        .animation(gateAnimation, value: auth.currentAdmin?.id)
    }

    private var gateAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.2)
        }
        return .spring(response: 0.5, dampingFraction: 0.9)
    }

    private var gateTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
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
