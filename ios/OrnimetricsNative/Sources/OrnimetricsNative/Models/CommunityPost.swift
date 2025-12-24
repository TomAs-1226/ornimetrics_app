import Foundation

struct CommunityPost: Identifiable {
    let id: String
    let author: String
    let body: String
    let createdAt: Date
    let photoURL: URL?
    let weather: String
    let humidity: Int
    let sensorTags: [String]

    static let sample = CommunityPost(
        id: UUID().uuidString,
        author: "Community Member",
        body: "Spotted a family of finches around the feeder at dusk. Food level holding steady and the humidity stayed below threshold.",
        createdAt: Date().addingTimeInterval(-3600),
        photoURL: nil,
        weather: "Partly Cloudy",
        humidity: 52,
        sensorTags: ["Low feeder traffic", "Evening", "North wind"]
    )
}
