import Foundation

struct DetectionPhoto: Identifiable {
    let id = UUID()
    let url: String
    let timestamp: Date
    let species: String?
    let weatherAtCapture: WeatherSnapshot?

    static func parseTimestamp(_ value: Any?) -> Date {
        if let intValue = value as? Int {
            if intValue > 100000000000 { return Date(timeIntervalSince1970: TimeInterval(intValue) / 1000) }
            if intValue > 1000000000 { return Date(timeIntervalSince1970: TimeInterval(intValue)) }
            return Date(timeIntervalSince1970: TimeInterval(intValue))
        }
        if let doubleValue = value as? Double {
            return Date(timeIntervalSince1970: doubleValue > 100000000000 ? doubleValue / 1000 : doubleValue)
        }
        if let stringValue = value as? String, let parsed = ISO8601DateFormatter().date(from: stringValue) {
            return parsed
        }
        return Date(timeIntervalSince1970: 0)
    }

    static func fromMap(_ map: [String: Any]) -> DetectionPhoto {
        let url = (map["image_url"] ?? map["url"] ?? "") as? String ?? ""
        let species = map["species"] as? String
        let timestamp = parseTimestamp(map["timestamp"])
        let weather = map["weather"] as? [String: Any]
        let snapshot = weather.map { WeatherSnapshot.fromMap($0) }
        return DetectionPhoto(url: url, timestamp: timestamp, species: species, weatherAtCapture: snapshot)
    }
}
