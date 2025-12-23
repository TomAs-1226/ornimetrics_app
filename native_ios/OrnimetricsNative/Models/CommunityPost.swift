import Foundation

struct CommunityPost: Identifiable {
    let id: String
    let title: String
    let body: String
    let author: String
    let createdAt: Date
    let weatherTag: String

    static let sample = CommunityPost(
        id: UUID().uuidString,
        title: "Feeder activity spike",
        body: "Noticed an increase in finch activity after switching to millet blend.",
        author: "Community Member",
        createdAt: Date(),
        weatherTag: "Sunny · 24°C"
    )
}
