import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let errorMessage {
                    GlassCard(title: "Could not load weather") {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }
                GlassCard(title: "Live weather", subtitle: appState.environment.locationName) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(appState.environment.temperatureC))°C")
                            .font(.system(size: 48, weight: .bold))
                        Text(appState.environment.condition)
                            .font(.title2)
                        Text("Feels like \(Int(appState.environment.feelsLikeC ?? appState.environment.temperatureC))°C")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    WeatherMetricCard(title: "Humidity", value: "\(Int(appState.environment.humidity))%")
                    WeatherMetricCard(title: "Wind", value: "\(Int(appState.environment.windKph ?? 0)) kph")
                    WeatherMetricCard(title: "Pressure", value: "\(Int(appState.environment.pressureMb ?? 0)) mb")
                    WeatherMetricCard(title: "UV Index", value: "\(Int(appState.environment.uvIndex ?? 0))")
                    WeatherMetricCard(title: "Visibility", value: "\(Int(appState.environment.visibilityKm ?? 0)) km")
                    WeatherMetricCard(title: "Dew Point", value: "\(Int(appState.environment.dewPointC ?? 0))°C")
                    WeatherMetricCard(
                        title: "Precip",
                        value: String(format: "%.1f mm", appState.environment.precipitationMm ?? 0)
                    )
                    WeatherMetricCard(title: "Precip Chance", value: "\(Int((appState.environment.precipitationChance ?? 0) * 100))%")
                }

                GlassCard(title: "Provider", subtitle: "Location status") {
                    HStack {
                        Image(systemName: "location.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.locationStatus)
                                .font(.headline)
                            Text(locationSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Request access") {
                            appState.locationService.requestAuthorization()
                            appState.locationService.requestLocation()
                            Haptics.impact(.light)
                        }
                        .buttonStyle(.bordered)
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
        .onAppear {
            if appState.config.weatherApiKey.isEmpty {
                errorMessage = "Weather API key is missing. Add WEATHER_API_KEY to load live conditions."
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await appState.refreshEnvironment()
        errorMessage = appState.config.weatherApiKey.isEmpty
            ? "Weather API key is missing. Add WEATHER_API_KEY to load live conditions."
            : nil
        Haptics.impact(.light)
    }

    private var locationSubtitle: String {
        if let location = appState.currentLocation {
            return String(format: "Lat %.4f, Lon %.4f", location.coordinate.latitude, location.coordinate.longitude)
        }
        if let error = appState.locationError {
            return error
        }
        return "Grant location access to attach real weather to your feed."
    }
}

private struct WeatherMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        GlassCard(title: title) {
            Text(value)
                .font(.title3.bold())
        }
    }
}
