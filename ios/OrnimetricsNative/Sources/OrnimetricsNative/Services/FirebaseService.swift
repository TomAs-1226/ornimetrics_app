import Foundation

struct FirebaseService {
    let config: AppConfig

    func signIn(email: String, password: String) async -> Bool {
        guard !config.firebaseApiKey.isEmpty else { return false }
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(config.firebaseApiKey)") else {
            return false
        }
        let payload: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode < 300
            }
            return false
        } catch {
            return false
        }
    }

    func fetchCommunityPosts() async -> [CommunityPost] {
        guard !config.firebaseDatabaseUrl.isEmpty else { return [] }
        let base = config.firebaseDatabaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/community_posts.json?orderBy=\"created_at\"&limitToLast=100"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            var posts: [CommunityPost] = []
            for (key, value) in json {
                if let map = value as? [String: Any] {
                    posts.append(CommunityPost.fromMap(id: key, map: map))
                }
            }
            return posts.sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    func uploadPost(caption: String, photoData: Data?, weather: WeatherSnapshot?, sensors: CommunitySensorTags, model: String) async -> CommunityPost? {
        guard !config.firebaseDatabaseUrl.isEmpty else { return nil }
        let base = config.firebaseDatabaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/community_posts.json"
        guard let url = URL(string: urlString) else { return nil }

        let post = CommunityPost(
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

        do {
            let payload = post.toMap()
            let data = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let (responseData, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let body = String(data: responseData, encoding: .utf8) ?? ""
                throw URLError(.badServerResponse, userInfo: ["body": body])
            }
            return post
        } catch {
            return nil
        }
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
