import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var aiEnabled = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "App configuration", subtitle: "Loaded from .env") {
                    ConfigRow(label: "Firebase project", value: appState.config.firebaseProjectId)
                    ConfigRow(label: "Firebase app ID", value: masked(appState.config.firebaseAppId))
                    ConfigRow(label: "Weather endpoint", value: appState.config.weatherEndpoint)
                    ConfigRow(label: "Weather API key", value: masked(appState.config.weatherApiKey))
                }

                GlassCard(title: "Apple Intelligence", subtitle: "On-device foundation models") {
                    Toggle("Enable on-device AI", isOn: $aiEnabled)
                    Text("Ecology insights use the on-device foundation model with privacy safeguards.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                GlassCard(title: "Device", subtitle: "Minimum iOS 18") {
                    Text("This native build targets iOS 18 and later for Apple Intelligence and Face ID features.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color.green.opacity(0.2), Color.yellow.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
    }

    private func masked(_ value: String) -> String {
        guard !value.isEmpty else { return "Missing" }
        return String(value.prefix(4)) + "••••" + String(value.suffix(2))
    }
}

struct ConfigRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value.isEmpty ? "Missing" : value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
