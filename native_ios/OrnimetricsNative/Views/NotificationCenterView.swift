import SwiftUI
import UserNotifications

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: OrnimetricsAppState
    @State private var foodThreshold = 20.0
    @State private var cooldownMinutes = 60.0

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Alerts")) {
                    Toggle("Enable Notifications", isOn: $appState.notificationsEnabled)
                    Slider(value: $foodThreshold, in: 5...50, step: 5) {
                        Text("Food Threshold")
                    } minimumValueLabel: {
                        Text("5%")
                    } maximumValueLabel: {
                        Text("50%")
                    }
                    Text("Alert when food drops below \(Int(foodThreshold))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Cooldown")) {
                    Slider(value: $cooldownMinutes, in: 15...240, step: 15)
                    Text("Cooldown: \(Int(cooldownMinutes)) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Request Permissions") {
                        Task {
                            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                            HapticsService.success()
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
        }
    }
}
