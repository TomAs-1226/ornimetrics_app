import Foundation

struct WeatherService {
    let config: AppConfig

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        guard !config.weatherApiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        let endpoint = config.weatherEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(endpoint)/current.json?key=\(config.weatherApiKey)&q=\(latitude),\(longitude)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(CurrentWeatherResponse.self, from: data)
        return WeatherSnapshot(
            condition: decoded.current.condition.text,
            temperatureC: decoded.current.tempC,
            humidity: decoded.current.humidity,
            windKph: decoded.current.windKph,
            locationName: decoded.location.name,
            updatedAt: Date()
        )
    }

    func fetchHistoricalWeather(latitude: Double, longitude: Double, date: Date) async throws -> WeatherSnapshot {
        guard !config.weatherApiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        let endpoint = config.weatherEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        let urlString = "\(endpoint)/history.json?key=\(config.weatherApiKey)&q=\(latitude),\(longitude)&dt=\(dateString)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(HistoricalWeatherResponse.self, from: data)
        return WeatherSnapshot(
            condition: decoded.forecast.forecastday.first?.day.condition.text ?? "Historical",
            temperatureC: decoded.forecast.forecastday.first?.day.avgtempC ?? 0,
            humidity: decoded.forecast.forecastday.first?.day.avghumidity ?? 0,
            windKph: decoded.forecast.forecastday.first?.day.maxwindKph ?? 0,
            locationName: decoded.location.name,
            updatedAt: date
        )
    }
}

private struct CurrentWeatherResponse: Decodable {
    let location: WeatherLocation
    let current: WeatherCurrent
}

private struct WeatherLocation: Decodable {
    let name: String
}

private struct WeatherCurrent: Decodable {
    let tempC: Double
    let humidity: Int
    let windKph: Double
    let condition: WeatherCondition

    enum CodingKeys: String, CodingKey {
        case tempC = "temp_c"
        case humidity
        case windKph = "wind_kph"
        case condition
    }
}

private struct WeatherCondition: Decodable {
    let text: String
}

private struct HistoricalWeatherResponse: Decodable {
    let location: WeatherLocation
    let forecast: ForecastContainer
}

private struct ForecastContainer: Decodable {
    let forecastday: [ForecastDay]
}

private struct ForecastDay: Decodable {
    let day: ForecastDayInfo
}

private struct ForecastDayInfo: Decodable {
    let avgtempC: Double
    let avghumidity: Int
    let maxwindKph: Double
    let condition: WeatherCondition

    enum CodingKeys: String, CodingKey {
        case avgtempC = "avgtemp_c"
        case avghumidity
        case maxwindKph = "maxwind_kph"
        case condition
    }
}
