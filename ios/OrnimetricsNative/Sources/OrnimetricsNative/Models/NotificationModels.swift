import Foundation

enum NotificationType: String, Codable, CaseIterable, Identifiable {
    case lowFood
    case clogged
    case cleaningDue
    case weatherBased
    case heavyUse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowFood: return "Low food"
        case .clogged: return "Clogged feeder"
        case .cleaningDue: return "Cleaning due"
        case .weatherBased: return "Weather cleaning"
        case .heavyUse: return "Heavy use"
        }
    }
}

enum WeatherSensitivity: String, Codable, CaseIterable, Identifiable {
    case normal
    case high

    var id: String { rawValue }
}

enum UsageSensitivity: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }
}

struct NotificationPreferences: Codable {
    var lowFoodEnabled: Bool = true
    var cloggedEnabled: Bool = true
    var cleaningReminderEnabled: Bool = true
    var cleaningIntervalDays: Int = 7
    var weatherBasedCleaningEnabled: Bool = true
    var weatherSensitivity: WeatherSensitivity = .normal
    var humidityThreshold: Double = 78
    var heavyUseEnabled: Bool = true
    var heavyUseSensitivity: UsageSensitivity = .normal
    var lowFoodThresholdPercent: Double = 20
    var progressNotificationsEnabled: Bool = true
    var heavyUseCooldownHours: Double = 12
    var weatherCooldownHours: Double = 12
    var lastCleaned: Date? = nil
}

struct NotificationEvent: Identifiable, Codable {
    let id: UUID
    let type: NotificationType
    let message: String
    let timestamp: Date
    let meta: [String: String]

    init(type: NotificationType, message: String, timestamp: Date = Date(), meta: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.message = message
        self.timestamp = timestamp
        self.meta = meta
    }
}

struct FoodLevelReading: Identifiable {
    let id = UUID()
    let percentFull: Double
    let timestamp: Date
}
