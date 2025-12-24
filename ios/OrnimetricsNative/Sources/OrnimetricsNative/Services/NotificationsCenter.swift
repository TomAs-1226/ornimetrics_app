import Foundation

@MainActor
final class NotificationsCenter: ObservableObject {
    @Published var preferences: NotificationPreferences
    @Published var events: [NotificationEvent]
    @Published var foodLevel: FoodLevelReading?
    @Published var permissionsPrompted: Bool

    private var foodTimer: Timer?
    private var sentLowFoodAlert = false

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
        permissionsPrompted = true
        UserDefaults.standard.set(true, forKey: promptedKey)
    }

    func simulateLowFood() {
        guard preferences.lowFoodEnabled else { return }
        emit(type: .lowFood, message: "Feeder food level is low. Time to refill!")
    }

    func simulateClogged() {
        guard preferences.cloggedEnabled else { return }
        emit(type: .clogged, message: "Possible feeder clog detected. Inspect the chute.")
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
        emit(type: .weatherBased, message: reason)
    }

    func triggerHeavyUse(reason: String) {
        guard preferences.heavyUseEnabled else { return }
        emit(type: .heavyUse, message: reason)
    }

    func startFoodLevelTracking() {
        stopFoodLevelTracking()
        foodTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self else { return }
            let nextPercent = max(0, (self.foodLevel?.percentFull ?? 0.8) - Double.random(in: 0.02...0.05))
            let reading = FoodLevelReading(percentFull: nextPercent * 100, timestamp: Date())
            self.foodLevel = reading
            if self.preferences.progressNotificationsEnabled {
                // keep the latest reading in memory for UI
            }
            if self.preferences.lowFoodEnabled && reading.percentFull <= self.preferences.lowFoodThresholdPercent {
                if !self.sentLowFoodAlert {
                    self.emit(type: .lowFood, message: "Food level at \(Int(reading.percentFull))%. Time to refill.")
                    self.sentLowFoodAlert = true
                }
            } else {
                self.sentLowFoodAlert = false
            }
        }
    }

    func stopFoodLevelTracking() {
        foodTimer?.invalidate()
        foodTimer = nil
    }

    private func emit(type: NotificationType, message: String) {
        let event = NotificationEvent(type: type, message: message, timestamp: Date())
        events.insert(event, at: 0)
        events = Array(events.prefix(25))
    }
}
