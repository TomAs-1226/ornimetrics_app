import Foundation
import UserNotifications

@MainActor
final class NotificationsCenter: ObservableObject {
    @Published var preferences: NotificationPreferences
    @Published var events: [NotificationEvent]
    @Published var foodLevel: FoodLevelReading?
    @Published var permissionsPrompted: Bool

    private var foodTimer: Timer?
    private var sentLowFoodAlert = false
    private var lastWeatherTrigger: Date?
    private var lastHeavyUseTrigger: Date?

    private let prefsKey = "ornimetrics.notification.preferences"
    private let promptedKey = "ornimetrics.notification.prompted"

    init() {
        self.preferences = NotificationPreferences()
        self.events = []
        self.permissionsPrompted = UserDefaults.standard.bool(forKey: promptedKey)
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: prefsKey),
           let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = decoded
        }
        permissionsPrompted = UserDefaults.standard.bool(forKey: promptedKey)
    }

    func updatePreferences(_ next: NotificationPreferences) {
        preferences = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }

    func markCleaned() {
        var next = preferences
        next.lastCleaned = Date()
        updatePreferences(next)
    }

    func requestPermissions() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                permissionsPrompted = true
                UserDefaults.standard.set(true, forKey: promptedKey)
                if granted == true {
                    center.getNotificationSettings { _ in }
                }
            }
        }
    }

    func triggerCleaningCheck() {
        guard preferences.cleaningReminderEnabled else { return }
        let interval = preferences.cleaningIntervalDays
        let last = preferences.lastCleaned
        let daysSince = last == nil ? interval + 1 : Calendar.current.dateComponents([.day], from: last!, to: Date()).day ?? interval + 1
        if daysSince >= interval {
            emit(type: .cleaningDue, message: "Cleaning due. It's been \(daysSince) day(s) since last cleaning.")
        }
    }

    func triggerWeatherCleaning(reason: String) {
        guard preferences.weatherBasedCleaningEnabled else { return }
        if let last = lastWeatherTrigger,
           Date().timeIntervalSince(last) < preferences.weatherCooldownHours * 3600 {
            return
        }
        emit(type: .weatherBased, message: reason)
        lastWeatherTrigger = Date()
    }

    func triggerHeavyUse(reason: String) {
        guard preferences.heavyUseEnabled else { return }
        if let last = lastHeavyUseTrigger,
           Date().timeIntervalSince(last) < preferences.heavyUseCooldownHours * 3600 {
            return
        }
        emit(type: .heavyUse, message: reason)
        lastHeavyUseTrigger = Date()
    }

    func startTelemetryTracking(databaseUrl: String) {
        guard !databaseUrl.isEmpty else { return }
        stopTelemetryTracking()
        foodTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.fetchTelemetry(databaseUrl: databaseUrl) }
        }
        Task { await fetchTelemetry(databaseUrl: databaseUrl) }
    }

    func stopTelemetryTracking() {
        foodTimer?.invalidate()
        foodTimer = nil
    }

    private func emit(type: NotificationType, message: String) {
        let event = NotificationEvent(type: type, message: message, timestamp: Date())
        events.insert(event, at: 0)
        events = Array(events.prefix(25))
        scheduleLocalNotification(type: type, message: message)
    }

    private func fetchTelemetry(databaseUrl: String) async {
        let base = databaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/feeder_status.json"
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let percent = json["food_level_percent"] as? Double ?? (json["food_level_percent"] as? NSNumber)?.doubleValue {
                let reading = FoodLevelReading(percentFull: percent, timestamp: Date())
                foodLevel = reading
                if preferences.lowFoodEnabled && percent <= preferences.lowFoodThresholdPercent {
                    if !sentLowFoodAlert {
                        emit(type: .lowFood, message: "Food level at \(Int(percent))%. Time to refill.")
                        sentLowFoodAlert = true
                    }
                } else {
                    sentLowFoodAlert = false
                }
            }

            if preferences.cloggedEnabled, let clogged = json["clogged"] as? Bool, clogged {
                emit(type: .clogged, message: "Possible feeder clog detected. Inspect the chute.")
            }

            if preferences.cleaningReminderEnabled, let cleaningDue = json["cleaning_due"] as? Bool, cleaningDue {
                emit(type: .cleaningDue, message: "Cleaning due. It's time to sanitize the feeder.")
            }

            if preferences.heavyUseEnabled, let score = json["heavy_use_score"] as? Double ?? (json["heavy_use_score"] as? NSNumber)?.doubleValue {
                let threshold: Double
                switch preferences.heavyUseSensitivity {
                case .low: threshold = 80
                case .normal: threshold = 65
                case .high: threshold = 50
                }
                if score >= threshold {
                    triggerHeavyUse(reason: "High feeder activity detected (score \(Int(score)) ≥ \(Int(threshold))).")
                }
            }
        } catch {
            // swallow telemetry errors for now
        }
    }

    private func scheduleLocalNotification(type: NotificationType, message: String) {
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = message
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
