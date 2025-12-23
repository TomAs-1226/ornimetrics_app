import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var appState: OrnimetricsAppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    weatherCard
                    humidityCard
                    Button {
                        Task { @MainActor in
                            await appState.refreshWeather()
                            HapticsService.success()
                        }
                    } label: {
                        Label("Refresh Weather", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Environment")
        }
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Conditions")
                .font(.headline)
            if let snapshot = appState.weatherSnapshot {
                Text(snapshot.condition)
                    .font(.title2.bold())
                Text("\(snapshot.temperatureC, specifier: "%.1f")°C · Wind \(snapshot.windKph, specifier: "%.0f") kph")
                    .foregroundStyle(.secondary)
            } else {
                Text("Fetching weather...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var humidityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Humidity")
                .font(.headline)
            Text("\(appState.weatherSnapshot?.humidity ?? 0, specifier: "%.0f")%")
                .font(.title.bold())
                .foregroundStyle(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
