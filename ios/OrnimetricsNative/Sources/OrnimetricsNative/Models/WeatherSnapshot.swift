import Foundation

struct WeatherSnapshot: Identifiable {
    let id = UUID()
    let condition: String
    let temperatureC: Double
    let humidity: Int
    let windKph: Double
    let locationName: String
    let updatedAt: Date

    static let placeholder = WeatherSnapshot(
        condition: "Clear",
        temperatureC: 21.0,
        humidity: 48,
        windKph: 6.0,
        locationName: "Current Location",
        updatedAt: Date()
    )
}
