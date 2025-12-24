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
}
