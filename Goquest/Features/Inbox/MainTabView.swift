import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "tray.full") }
            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            NavigationStack { ContractsView() }
                .tabItem { Label("Contracts", systemImage: "signature") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
