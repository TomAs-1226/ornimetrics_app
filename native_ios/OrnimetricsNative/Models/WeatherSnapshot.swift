import Foundation

struct WeatherSnapshot: Identifiable {
    let id = UUID()
    let condition: String
    let temperatureC: Double
    let humidity: Double
    let windKph: Double
    let fetchedAt: Date

    static let placeholder = WeatherSnapshot(
        condition: "Unavailable",
        temperatureC: 0,
        humidity: 0,
        windKph: 0,
        fetchedAt: Date()
    )
}
