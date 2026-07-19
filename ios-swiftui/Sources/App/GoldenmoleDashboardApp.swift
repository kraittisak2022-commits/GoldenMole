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
    /// Becomes true once bootstrap finishes (success or config error).
    @Published var isReady = false

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
    @EnvironmentObject private var bootstrap: AppBootstrap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSplash = true
    @State private var minDurationElapsed = false

    private var canDismissSplash: Bool {
        bootstrap.isReady && minDurationElapsed
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
                    .environmentObject(auth)
                    .environmentObject(bootstrap.appState)
                    .transition(contentEnterTransition)
            }
        }
        .animation(gateAnimation, value: showSplash)
        .task {
            let nanos: UInt64 = reduceMotion ? 400_000_000 : 1_400_000_000
            try? await Task.sleep(nanoseconds: nanos)
            minDurationElapsed = true
            dismissSplashIfReady()
        }
        .onChange(of: bootstrap.isReady) { ready in
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

/// Holds `@ObservedObject` on AuthService so `currentAdmin` changes trigger navigation.
private struct AuthGateView: View {
    @ObservedObject var auth: AuthService
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
