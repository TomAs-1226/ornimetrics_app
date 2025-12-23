import Foundation

struct FeederStatus {
    let foodLevel: Double
    let hopperCapacity: Double
    let lastRefill: Date
    let location: Location
    let nextMaintenance: Date
    let notificationsEnabled: Bool

    static let sample = FeederStatus(
        foodLevel: 0.62,
        hopperCapacity: 100,
        lastRefill: Date().addingTimeInterval(-86400 * 3),
        location: Location(latitude: 37.7749, longitude: -122.4194),
        nextMaintenance: Date().addingTimeInterval(86400 * 7),
        notificationsEnabled: true
    )
}

struct Location {
    let latitude: Double
    let longitude: Double
}
