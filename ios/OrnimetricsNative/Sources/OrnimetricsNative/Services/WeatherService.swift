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
            humidity: Double(decoded.current.humidity),
            precipitationChance: decoded.current.precipitationChance,
            windKph: decoded.current.windKph,
            pressureMb: decoded.current.pressureMb,
            uvIndex: decoded.current.uvIndex,
            visibilityKm: decoded.current.visibilityKm,
            dewPointC: decoded.current.dewPointC,
            feelsLikeC: decoded.current.feelsLikeC,
            precipitationMm: decoded.current.precipitationMm,
            isRaining: decoded.current.isRaining,
            isSnowing: decoded.current.isSnowing,
            isHailing: decoded.current.isHailing,
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
            humidity: Double(decoded.forecast.forecastday.first?.day.avghumidity ?? 0),
            precipitationChance: (decoded.forecast.forecastday.first?.day.dailyChanceOfRain).map { $0 / 100.0 },
            windKph: decoded.forecast.forecastday.first?.day.maxwindKph,
            pressureMb: nil,
            uvIndex: decoded.forecast.forecastday.first?.day.uvIndex,
            visibilityKm: nil,
            dewPointC: nil,
            feelsLikeC: decoded.forecast.forecastday.first?.day.avgFeelsLikeC,
            precipitationMm: decoded.forecast.forecastday.first?.day.totalPrecipMm,
            isRaining: decoded.forecast.forecastday.first?.day.dailyChanceOfRain ?? 0 > 30,
            isSnowing: decoded.forecast.forecastday.first?.day.dailyChanceOfSnow ?? 0 > 30,
            isHailing: false,
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
    let pressureMb: Double?
    let uvIndex: Double?
    let visibilityKm: Double?
    let dewPointC: Double?
    let feelsLikeC: Double?
    let precipitationMm: Double?
    let condition: WeatherCondition
    let cloudPercent: Double?

    enum CodingKeys: String, CodingKey {
        case tempC = "temp_c"
        case humidity
        case windKph = "wind_kph"
        case pressureMb = "pressure_mb"
        case uvIndex = "uv"
        case visibilityKm = "vis_km"
        case dewPointC = "dewpoint_c"
        case feelsLikeC = "feelslike_c"
        case precipitationMm = "precip_mm"
        case condition
        case cloudPercent = "cloud"
    }

    var isRaining: Bool { (precipitationMm ?? 0) > 0.1 }
    var isSnowing: Bool { false }
    var isHailing: Bool { false }
    var precipitationChance: Double? {
        guard let cloudPercent else { return nil }
        return cloudPercent / 100.0
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
    let dailyChanceOfRain: Double?
    let dailyChanceOfSnow: Double?
    let uvIndex: Double?
    let totalPrecipMm: Double?
    let avgFeelsLikeC: Double?

    enum CodingKeys: String, CodingKey {
        case avgtempC = "avgtemp_c"
        case avghumidity
        case maxwindKph = "maxwind_kph"
        case condition
        case dailyChanceOfRain = "daily_chance_of_rain"
        case dailyChanceOfSnow = "daily_chance_of_snow"
        case uvIndex = "uv"
        case totalPrecipMm = "totalprecip_mm"
        // IMPORTANT: do NOT put avgFeelsLikeC here unless you have a distinct real key.
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        avgtempC = try container.decode(Double.self, forKey: .avgtempC)
        avghumidity = try container.decode(Int.self, forKey: .avghumidity)
        maxwindKph = try container.decode(Double.self, forKey: .maxwindKph)
        condition = try container.decode(WeatherCondition.self, forKey: .condition)
        dailyChanceOfRain = try container.decodeIfPresent(StringOrDouble.self, forKey: .dailyChanceOfRain)?.value
        dailyChanceOfSnow = try container.decodeIfPresent(StringOrDouble.self, forKey: .dailyChanceOfSnow)?.value
        uvIndex = try container.decodeIfPresent(Double.self, forKey: .uvIndex)
        totalPrecipMm = try container.decodeIfPresent(Double.self, forKey: .totalPrecipMm)

        // WeatherAPI history often doesn't provide "avg feels like".
        // Use avgtempC as a reasonable fallback, or set nil.
        avgFeelsLikeC = avgtempC
    }
}

private struct StringOrDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self), let doubleValue = Double(stringValue) {
            value = doubleValue
        } else {
            value = 0
        }
    }
}
