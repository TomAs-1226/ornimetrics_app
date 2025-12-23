import Foundation

struct DetectionService {
    let config: AppConfig

    func fetchRecentPhotos(limit: Int = 50) async -> [DetectionPhoto] {
        guard !config.firebaseDatabaseUrl.isEmpty else { return [] }
        let base = config.firebaseDatabaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/photo_snapshots.json?orderBy=\"timestamp\"&limitToLast=\(limit)"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            var photos: [DetectionPhoto] = []
            for (_, value) in json {
                if let map = value as? [String: Any] {
                    photos.append(DetectionPhoto.fromMap(map))
                }
            }
            return photos.sorted(by: { $0.timestamp > $1.timestamp })
        } catch {
            return []
        }
    }
}
