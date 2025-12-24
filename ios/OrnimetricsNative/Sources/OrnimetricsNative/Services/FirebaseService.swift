import Foundation

struct FirebaseService {
    let config: AppConfig

    func signIn(email: String, password: String) async -> Bool {
        guard !config.firebaseApiKey.isEmpty else { return false }
        return !email.isEmpty && !password.isEmpty
    }

    func fetchCommunityPosts() async -> [CommunityPost] {
        return [CommunityPost.sample]
    }

    func uploadPost(caption: String, photoData: Data?, weather: WeatherSnapshot?, sensors: CommunitySensorTags, model: String) async -> CommunityPost? {
        return CommunityPost(
            id: UUID().uuidString,
            author: "You",
            caption: caption,
            createdAt: Date(),
            imageURL: nil,
            imageData: photoData,
            weather: weather,
            timeOfDayTag: timeOfDayLabel(for: Date()),
            model: model,
            sensors: sensors
        )
    }

    private func timeOfDayLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return "Morning"
        case 11..<15: return "Midday"
        case 15..<19: return "Afternoon"
        case 19..<22: return "Dusk"
        default: return "Night"
        }
    }
}
