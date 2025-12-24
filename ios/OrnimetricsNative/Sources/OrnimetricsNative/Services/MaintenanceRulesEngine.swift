import Foundation

struct MaintenanceRulesEngine {
    static func evaluateWeather(_ snapshot: WeatherSnapshot, preferences: NotificationPreferences, notifications: NotificationsCenter) {
        guard preferences.weatherBasedCleaningEnabled else { return }
        if snapshot.isRaining || snapshot.isSnowing || snapshot.isHailing {
            notifications.triggerWeatherCleaning(reason: "Weather event detected (\(snapshot.condition)). Consider cleaning the feeder.")
        } else if snapshot.humidity >= preferences.humidityThreshold {
            notifications.triggerWeatherCleaning(reason: "Humidity is \(Int(snapshot.humidity))%. Cleaning recommended.")
        }
    }
}
