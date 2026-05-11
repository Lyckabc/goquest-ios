import SwiftUI

@main
struct GoquestApp: App {
    @StateObject private var auth = AuthService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
