import Foundation

struct WeatherSnapshot: Identifiable {
    let id = UUID()
    let condition: String
    let temperatureC: Double
    let humidity: Double
    let precipitationChance: Double?
    let windKph: Double?
    let pressureMb: Double?
    let uvIndex: Double?
    let visibilityKm: Double?
    let dewPointC: Double?
    let feelsLikeC: Double?
    let precipitationMm: Double?
    let isRaining: Bool
    let isSnowing: Bool
    let isHailing: Bool
    let locationName: String
    let updatedAt: Date

    static let placeholder = WeatherSnapshot(
        condition: "Clear",
        temperatureC: 21.0,
        humidity: 48,
        precipitationChance: 0.1,
        windKph: 6.0,
        pressureMb: 1012,
        uvIndex: 4,
        visibilityKm: 10,
        dewPointC: 10,
        feelsLikeC: 21,
        precipitationMm: 0,
        isRaining: false,
        isSnowing: false,
        isHailing: false,
        locationName: "Current Location",
        updatedAt: Date()
    )

    static func fromMap(_ map: [String: Any]) -> WeatherSnapshot {
        WeatherSnapshot(
            condition: map["condition"] as? String ?? "Unknown",
            temperatureC: (map["temperatureC"] as? NSNumber)?.doubleValue ?? 0,
            humidity: (map["humidity"] as? NSNumber)?.doubleValue ?? 0,
            precipitationChance: (map["precipitationChance"] as? NSNumber)?.doubleValue,
            windKph: (map["windKph"] as? NSNumber)?.doubleValue,
            pressureMb: (map["pressureMb"] as? NSNumber)?.doubleValue,
            uvIndex: (map["uvIndex"] as? NSNumber)?.doubleValue,
            visibilityKm: (map["visibilityKm"] as? NSNumber)?.doubleValue,
            dewPointC: (map["dewPointC"] as? NSNumber)?.doubleValue,
            feelsLikeC: (map["feelsLikeC"] as? NSNumber)?.doubleValue,
            precipitationMm: (map["precipitationMm"] as? NSNumber)?.doubleValue,
            isRaining: map["isRaining"] as? Bool ?? false,
            isSnowing: map["isSnowing"] as? Bool ?? false,
            isHailing: map["isHailing"] as? Bool ?? false,
            locationName: map["locationName"] as? String ?? "Snapshot",
            updatedAt: Date()
        )
    }
}
