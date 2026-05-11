import SwiftUI

@main
struct GoquestApp: App {
    @StateObject private var auth = AuthService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Best-effort: try silent refresh on cold launch.
        Task { await AuthService.shared.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .onOpenURL { url in
                    // ZITADEL OIDC callback (home.toji.goquest://oauth2redirect/zitadel)
                    AuthService.shared.handleCallback(url: url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-arm the calendar BG refresh every time we leave the
            // foreground — iOS only honors a submitted request, so this
            // keeps the cadence alive across app sessions.
            if newPhase == .background {
                BackgroundCalendarSync.shared.scheduleNextRefresh()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        switch auth.state {
        case .loading:
            ProgressView()
        case .loggedOut:
            LoginView()
        case .loggedIn:
            MainTabView()
        }
    }
}
