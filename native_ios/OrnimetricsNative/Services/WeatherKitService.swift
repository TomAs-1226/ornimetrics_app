import Foundation
import CoreLocation
import WeatherKit

struct WeatherKitService {
    private let service = WeatherService()

    func fetchWeather(for location: CLLocation) async throws -> WeatherSnapshot {
        let weather = try await service.weather(for: location)
        return WeatherSnapshot(
            condition: weather.currentWeather.condition.description,
            temperatureC: weather.currentWeather.temperature.converted(to: .celsius).value,
            humidity: weather.currentWeather.humidity * 100,
            windKph: weather.currentWeather.wind.speed.converted(to: .kilometersPerHour).value,
            fetchedAt: Date()
        )
    }
}
