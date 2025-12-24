import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case environment
    case community
    case gallery
    case species
    case notifications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .environment: return "Environment"
        case .community: return "Community"
        case .gallery: return "Gallery"
        case .species: return "Species"
        case .notifications: return "Notifications"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .environment: return "cloud.sun"
        case .community: return "person.3.fill"
        case .gallery: return "photo.on.rectangle.angled"
        case .species: return "pawprint"
        case .notifications: return "bell.badge"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .dashboard

    // Tabs you want on compact width (phone). You can add .gallery/.species if you want them as tabs too.
    private let tabSections: [AppSection] = [.dashboard, .environment, .community, .notifications, .settings]

    var body: some View {
        Group {
            // iPad split view when available
            if #available(iOS 16.0, *), horizontalSizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationContainer {
                        detailView(for: selection)
                            .navigationTitle(selection.title)
                    }
                }
            } else {
                TabView(selection: $selection) {
                    ForEach(tabSections) { section in
                        NavigationContainer {
                            detailView(for: section)
                                .navigationTitle(section.title)
                        }
                        .tabItem { Label(section.title, systemImage: section.systemImage) }
                        .tag(section)
                    }
                }
            }
        }
        .applyMintTintCompat()
    }

    // MARK: - Sidebar (iPad)
    private var sidebar: some View {
        List {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 12) {
                        Label(section.title, systemImage: section.systemImage)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selection == section ? Color.mint.opacity(0.18) : Color.clear
                )
            }
        }
        .navigationTitle("Ornimetrics")
    }

    // MARK: - Routing
    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .environment:
            EnvironmentView()
        case .community:
            CommunityView()
        case .gallery:
            GalleryView()
        case .species:
            SpeciesView()
        case .notifications:
            NotificationsView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Navigation compatibility wrapper
private struct NavigationContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
            .navigationViewStyle(.stack)
        }
    }
}

// MARK: - Tint compatibility
private extension View {
    @ViewBuilder
    func applyMintTintCompat() -> some View {
        if #available(iOS 15.0, *) {
            self.tint(.mint)
        } else {
            self.accentColor(.mint)
        }
    }
}
