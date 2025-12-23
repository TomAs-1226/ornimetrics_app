import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case environment
    case community
    case notifications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .environment: return "Environment"
        case .community: return "Community"
        case .notifications: return "Notifications"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .environment: return "cloud.sun"
        case .community: return "person.3.fill"
        case .notifications: return "bell.badge"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .dashboard

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List(AppSection.allCases, selection: $selection) { section in
                        Label(section.title, systemImage: section.systemImage)
                    }
                    .navigationTitle("Ornimetrics")
                } detail: {
                    detailView(for: selection)
                        .navigationTitle(selection.title)
                }
            } else {
                TabView(selection: $selection) {
                    detailView(for: .dashboard)
                        .tabItem { Label(AppSection.dashboard.title, systemImage: AppSection.dashboard.systemImage) }
                        .tag(AppSection.dashboard)
                    detailView(for: .environment)
                        .tabItem { Label(AppSection.environment.title, systemImage: AppSection.environment.systemImage) }
                        .tag(AppSection.environment)
                    detailView(for: .community)
                        .tabItem { Label(AppSection.community.title, systemImage: AppSection.community.systemImage) }
                        .tag(AppSection.community)
                    detailView(for: .notifications)
                        .tabItem { Label(AppSection.notifications.title, systemImage: AppSection.notifications.systemImage) }
                        .tag(AppSection.notifications)
                    detailView(for: .settings)
                        .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
                        .tag(AppSection.settings)
                }
            }
        }
        .tint(.mint)
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .environment:
            EnvironmentView()
        case .community:
            CommunityView()
        case .notifications:
            NotificationsView()
        case .settings:
            SettingsView()
        }
    }
}
