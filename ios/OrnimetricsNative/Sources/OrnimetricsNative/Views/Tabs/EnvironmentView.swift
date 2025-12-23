import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Live weather", subtitle: appState.environment.locationName) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(appState.environment.temperatureC))°C")
                            .font(.system(size: 48, weight: .bold))
                        Text(appState.environment.condition)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 16) {
                    GlassCard(title: "Humidity") {
                        Text("\(appState.environment.humidity)%")
                            .font(.title2.bold())
                    }
                    GlassCard(title: "Wind") {
                        Text("\(Int(appState.environment.windKph)) kph")
                            .font(.title2.bold())
                    }
                }

                GlassCard(title: "Historical context", subtitle: "From tagged photos") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("View the weather conditions attached to every photo in your gallery and community posts.")
                            .foregroundStyle(.secondary)
                        Button("Refresh weather") {
                            Task {
                                await refresh()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.2), Color.indigo.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .refreshable {
            await refresh()
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await appState.refreshEnvironment()
        Haptics.impact(.light)
    }
}
