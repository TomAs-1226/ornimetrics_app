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

    func uploadPost(body: String, photoData: Data?) async -> CommunityPost? {
        return CommunityPost(
            id: UUID().uuidString,
            author: "You",
            body: body,
            createdAt: Date(),
            photoURL: nil,
            weather: "Clear",
            humidity: 46,
            sensorTags: ["Manual upload"]
        )
    }
}
