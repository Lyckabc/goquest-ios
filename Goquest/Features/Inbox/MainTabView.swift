import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "tray.full") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
