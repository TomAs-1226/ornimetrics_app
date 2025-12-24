import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("pref_dark_mode") private var darkMode = false
    @AppStorage("pref_haptics_enabled") private var hapticsEnabled = true
    @AppStorage("pref_animations_enabled") private var animationsEnabled = true
    @AppStorage("pref_auto_refresh_enabled") private var autoRefreshEnabled = false
    @AppStorage("pref_auto_refresh_interval") private var autoRefreshInterval = 60.0
    @AppStorage("pref_ai_model") private var selectedAiModel = "gpt-4o-mini"
    @State private var aiEnabled = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Appearance") {
                    Toggle("Dark mode", isOn: $darkMode)
                    Text("Accent tint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    WrapHStack(items: accentChoices) { color in
                        Button {
                            appState.updateAccentColor(hex: color.hex)
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: appState.accentColorHex == color.hex ? 3 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                GlassCard(title: "App configuration", subtitle: "Loaded from .env") {
                    ConfigRow(label: "Firebase project", value: appState.config.firebaseProjectId)
                    ConfigRow(label: "Firebase app ID", value: masked(appState.config.firebaseAppId))
                    ConfigRow(label: "Firebase database", value: appState.config.firebaseDatabaseUrl)
                    ConfigRow(label: "Weather endpoint", value: appState.config.weatherEndpoint)
                    ConfigRow(label: "Weather API key", value: masked(appState.config.weatherApiKey))
                    ConfigRow(label: "OpenAI API key", value: masked(appState.config.openAiApiKey))
                }

                GlassCard(title: "Feedback") {
                    Toggle("Enable haptic feedback", isOn: $hapticsEnabled)
                    Toggle("Enable animations", isOn: $animationsEnabled)
                }

                GlassCard(title: "Auto-refresh data") {
                    Toggle("Auto-refresh", isOn: $autoRefreshEnabled)
                        .onChange(of: autoRefreshEnabled) { _ in
                            appState.configureAutoRefresh()
                        }
                    if autoRefreshEnabled {
                        Text("Every \(Int(autoRefreshInterval)) sec")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $autoRefreshInterval, in: 10...300, step: 10)
                            .onChange(of: autoRefreshInterval) { _ in
                                appState.configureAutoRefresh()
                            }
                    }
                }

                GlassCard(title: "Preferred AI model") {
                    Picker("Model", selection: $selectedAiModel) {
                        Text("GPT-4o Mini").tag("gpt-4o-mini")
                        Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
                        Text("GPT 5.1").tag("gpt-5.1")
                        Text("GPT 5.2").tag("gpt-5.2")
                    }
                    .pickerStyle(.menu)
                }

                GlassCard(title: "Apple Intelligence", subtitle: "On-device foundation models") {
                    Toggle("Enable on-device AI", isOn: $aiEnabled)
                    Text("Ecology insights use the on-device foundation model with privacy safeguards.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                GlassCard(title: "Feeder notifications") {
                    NavigationLink("Open notification center") {
                        NotificationsView(notifications: appState.notificationsCenter)
                    }
                }

                GlassCard(title: "Feeder maintenance") {
                    let lastCleaned = appState.notificationsCenter.preferences.lastCleaned
                    Text(lastCleaned == nil
                         ? "No cleaning date recorded"
                         : "Last cleaned: \(lastCleaned!.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Mark cleaned today") {
                        appState.notificationsCenter.markCleaned()
                        Haptics.success()
                    }
                    .buttonStyle(.borderedProminent)
                }

                GlassCard(title: "Clear AI analysis cache") {
                    Button("Clear AI analysis cache") {
                        appState.aiAnalysis = ""
                        Haptics.impact(.light)
                    }
                    .buttonStyle(.bordered)
                }

                GlassCard(title: "App version") {
                    Text("1.1.0")
                        .font(.headline)
                    Text("Monitor wildlife detections, track biodiversity, and receive AI guidance on feeder care and habitat safety.")
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
        .onAppear {
            appState.configureAutoRefresh()
        }
    }

    private func masked(_ value: String) -> String {
        guard !value.isEmpty else { return "Missing" }
        return String(value.prefix(4)) + "••••" + String(value.suffix(2))
    }

    private var accentChoices: [AccentChoice] {
        [
            AccentChoice(hex: "#2ECC71", swiftUIColor: .green),
            AccentChoice(hex: "#F39C12", swiftUIColor: .orange),
            AccentChoice(hex: "#1ABC9C", swiftUIColor: .teal),
            AccentChoice(hex: "#8E44AD", swiftUIColor: .purple),
            AccentChoice(hex: "#E91E63", swiftUIColor: .pink),
            AccentChoice(hex: "#3498DB", swiftUIColor: .blue),
            AccentChoice(hex: "#607D8B", swiftUIColor: .blue.opacity(0.6))
        ]
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

private struct AccentChoice: Hashable {
    let hex: String
    let swiftUIColor: Color
}
