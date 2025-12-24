import SwiftUI

struct NotificationsView: View {
    @ObservedObject var notifications: NotificationsCenter

    init(notifications: NotificationsCenter) {
        self.notifications = notifications
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Alerts") {
                    Toggle("Low/empty food", isOn: Binding(
                        get: { notifications.preferences.lowFoodEnabled },
                        set: { newValue in updatePrefs { $0.lowFoodEnabled = newValue } }
                    ))
                    Text("Notify when under \(Int(notifications.preferences.lowFoodThresholdPercent))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { notifications.preferences.lowFoodThresholdPercent },
                            set: { newValue in updatePrefs { $0.lowFoodThresholdPercent = newValue } }
                        ),
                        in: 5...60,
                        step: 5
                    )

                    Toggle("Clogged feeder alerts", isOn: Binding(
                        get: { notifications.preferences.cloggedEnabled },
                        set: { newValue in updatePrefs { $0.cloggedEnabled = newValue } }
                    ))

                    Toggle("Cleaning reminders", isOn: Binding(
                        get: { notifications.preferences.cleaningReminderEnabled },
                        set: { newValue in updatePrefs { $0.cleaningReminderEnabled = newValue } }
                    ))

                    if notifications.preferences.cleaningReminderEnabled {
                        Text("Every \(notifications.preferences.cleaningIntervalDays) day(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(notifications.preferences.cleaningIntervalDays) },
                                set: { newValue in updatePrefs { $0.cleaningIntervalDays = Int(newValue) } }
                            ),
                            in: 3...60,
                            step: 3
                        )
                    }

                    Toggle("Show progress notifications", isOn: Binding(
                        get: { notifications.preferences.progressNotificationsEnabled },
                        set: { newValue in updatePrefs { $0.progressNotificationsEnabled = newValue } }
                    ))

                    HStack {
                        Text(notifications.preferences.lastCleaned == nil
                             ? "Last cleaned: not recorded"
                             : "Last cleaned: \(notifications.preferences.lastCleaned!.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                        Spacer()
                        Button("Mark cleaned today") {
                            notifications.markCleaned()
                            Haptics.success()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                GlassCard(title: "Maintenance rules") {
                    Toggle("Weather-based cleaning prompts", isOn: Binding(
                        get: { notifications.preferences.weatherBasedCleaningEnabled },
                        set: { newValue in updatePrefs { $0.weatherBasedCleaningEnabled = newValue } }
                    ))
                    Text("Triggers on rain/snow/hail or humidity ≥ \(Int(notifications.preferences.humidityThreshold))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Weather sensitivity", selection: Binding(
                        get: { notifications.preferences.weatherSensitivity },
                        set: { newValue in updatePrefs { $0.weatherSensitivity = newValue } }
                    )) {
                        Text("Normal").tag(WeatherSensitivity.normal)
                        Text("High").tag(WeatherSensitivity.high)
                    }
                    .pickerStyle(.segmented)

                    Slider(
                        value: Binding(
                            get: { notifications.preferences.humidityThreshold },
                            set: { newValue in updatePrefs { $0.humidityThreshold = newValue } }
                        ),
                        in: 50...95,
                        step: 5
                    )

                    Toggle("Heavy use alerts", isOn: Binding(
                        get: { notifications.preferences.heavyUseEnabled },
                        set: { newValue in updatePrefs { $0.heavyUseEnabled = newValue } }
                    ))

                    Picker("Usage sensitivity", selection: Binding(
                        get: { notifications.preferences.heavyUseSensitivity },
                        set: { newValue in updatePrefs { $0.heavyUseSensitivity = newValue } }
                    )) {
                        Text("Low").tag(UsageSensitivity.low)
                        Text("Normal").tag(UsageSensitivity.normal)
                        Text("High").tag(UsageSensitivity.high)
                    }
                    .pickerStyle(.segmented)
                }

                GlassCard(title: "Food level") {
                    let percent = notifications.foodLevel?.percentFull ?? 100
                    Text("\(Int(percent))% full")
                        .font(.title2.bold())
                    ProgressView(value: percent, total: 100)
                        .tint(.mint)
                    Button("Simulate low food") {
                        notifications.simulateLowFood()
                    }
                    .buttonStyle(.bordered)
                }

                GlassCard(title: "Recent notification events") {
                    if notifications.events.isEmpty {
                        Text("No notifications yet. Connect your feeder to start receiving production alerts.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(notifications.events) { event in
                                HStack {
                                    Image(systemName: iconName(for: event.type))
                                    VStack(alignment: .leading) {
                                        Text(event.message)
                                            .font(.subheadline)
                                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear {
            notifications.startFoodLevelTracking()
        }
    }

    private func updatePrefs(_ update: (inout NotificationPreferences) -> Void) {
        var next = notifications.preferences
        update(&next)
        notifications.updatePreferences(next)
    }

    private func iconName(for type: NotificationType) -> String {
        switch type {
        case .lowFood: return "drop.triangle"
        case .clogged: return "exclamationmark.triangle"
        case .cleaningDue: return "sparkles"
        case .weatherBased: return "cloud.rain"
        case .heavyUse: return "waveform.path.ecg"
        }
    }
}
