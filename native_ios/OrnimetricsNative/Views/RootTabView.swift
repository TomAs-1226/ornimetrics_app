import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: OrnimetricsAppState

    var body: some View {
        TabView {
            FeederDashboardView()
                .tabItem {
                    Label("Feeder", systemImage: "leaf")
                }
            EnvironmentView()
                .tabItem {
                    Label("Environment", systemImage: "cloud.sun")
                }
            CommunityCenterView()
                .tabItem {
                    Label("Community", systemImage: "person.3")
                }
            NotificationCenterView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.badge")
                }
        }
        .tint(.green)
    }
}
