import Foundation

struct CommunitySensorTags: Hashable, Codable {
    var lowFood: Bool
    var clogged: Bool
    var cleaningDue: Bool
}

struct CommunityPost: Identifiable, Hashable {
    let id: String
    let author: String
    let caption: String
    let createdAt: Date
    let imageURL: URL?
    let imageData: Data?
    let weather: WeatherSnapshot?
    let timeOfDayTag: String
    let model: String
    let sensors: CommunitySensorTags

    static let sample = CommunityPost(
        id: UUID().uuidString,
        author: "Community Member",
        caption: "Spotted a family of finches around the feeder at dusk. Food level holding steady and the humidity stayed below threshold.",
        createdAt: Date().addingTimeInterval(-3600),
        imageURL: nil,
        imageData: nil,
        weather: .placeholder,
        timeOfDayTag: "Dusk",
        model: "gpt-4o-mini",
        sensors: CommunitySensorTags(lowFood: false, clogged: false, cleaningDue: true)
    )

    static func fromMap(id: String, map: [String: Any]) -> CommunityPost {
        let author = map["author"] as? String ?? "anon"
        let caption = map["caption"] as? String ?? ""
        let imageUrl = map["image_url"] as? String
        let base64 = map["image_base64"] as? String
        let imageData = decodeInlineImage(base64)
        let createdAt = parseTimestamp(map["created_at"])
        let timeOfDay = map["time_of_day"] as? String ?? "daytime"
        let model = map["model"] as? String ?? "Ornimetrics O1 feeder"
        let sensors = CommunitySensorTags(
            lowFood: (map["sensors"] as? [String: Any])?["lowFood"] as? Bool ?? false,
            clogged: (map["sensors"] as? [String: Any])?["clogged"] as? Bool ?? false,
            cleaningDue: (map["sensors"] as? [String: Any])?["cleaningDue"] as? Bool ?? false
        )
        let weather = (map["weather"] as? [String: Any]).map { WeatherSnapshot.fromMap($0) }
        return CommunityPost(
            id: id,
            author: author,
            caption: caption,
            createdAt: createdAt,
            imageURL: imageUrl.flatMap(URL.init(string:)),
            imageData: imageData,
            weather: weather,
            timeOfDayTag: timeOfDay,
            model: model,
            sensors: sensors
        )
    }

    func toMap() -> [String: Any] {
        var output: [String: Any] = [
            "author": author,
            "caption": caption,
            "time_of_day": timeOfDayTag,
            "model": model,
            "sensors": [
                "lowFood": sensors.lowFood,
                "clogged": sensors.clogged,
                "cleaningDue": sensors.cleaningDue
            ],
            "created_at": [".sv": "timestamp"]
        ]
        if let imageURL {
            output["image_url"] = imageURL.absoluteString
        }
        if let imageData {
            let base64 = imageData.base64EncodedString()
            output["image_base64"] = "data:image/jpeg;base64,\(base64)"
        }
        if let weather {
            output["weather"] = [
                "condition": weather.condition,
                "temperatureC": weather.temperatureC,
                "humidity": weather.humidity,
                "precipitationChance": weather.precipitationChance as Any,
                "windKph": weather.windKph as Any,
                "pressureMb": weather.pressureMb as Any,
                "uvIndex": weather.uvIndex as Any,
                "visibilityKm": weather.visibilityKm as Any,
                "dewPointC": weather.dewPointC as Any,
                "feelsLikeC": weather.feelsLikeC as Any,
                "precipitationMm": weather.precipitationMm as Any,
                "isRaining": weather.isRaining,
                "isSnowing": weather.isSnowing,
                "isHailing": weather.isHailing,
                "locationName": weather.locationName,
                "fetchedAt": weather.updatedAt.iso8601String
            ]
        }
        return output
    }

    private static func parseTimestamp(_ value: Any?) -> Date {
        if let intValue = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(intValue) / 1000)
        }
        if let doubleValue = value as? Double {
            return Date(timeIntervalSince1970: doubleValue / 1000)
        }
        if let stringValue = value as? String, let parsed = ISO8601DateFormatter().date(from: stringValue) {
            return parsed
        }
        return Date()
    }

    private static func decodeInlineImage(_ data: String?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        let cleaned = data.starts(with: "data:") ? data.split(separator: ",").last.map(String.init) ?? data : data
        return Data(base64Encoded: cleaned)
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
