import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var feederStatus = FeederStatus.sample
    @Published var environment = WeatherSnapshot.placeholder
    @Published var communityPosts: [CommunityPost] = []
    @Published var isAuthenticated = false
    @Published var aiSummary: String = ""
    @Published var detectionPhotos: [DetectionPhoto] = []
    @Published var speciesCounts: [String: Int] = [:]
    @Published var totalDetections: Int = 0

    let config: AppConfig
    let weatherService: WeatherService
    let firebaseService: FirebaseService
    let appleIntelligenceService: AppleIntelligenceService
    let detectionService: DetectionService

    init(config: AppConfig) {
        self.config = config
        self.weatherService = WeatherService(config: config)
        self.firebaseService = FirebaseService(config: config)
        self.appleIntelligenceService = AppleIntelligenceService()
        self.detectionService = DetectionService(config: config)
    }

    func bootstrap() async {
        await refreshEnvironment()
        await loadCommunityFeed()
        await loadDetections()
    }

    func refreshEnvironment() async {
        do {
            let snapshot = try await weatherService.fetchCurrentWeather(latitude: feederStatus.location.latitude,
                                                                        longitude: feederStatus.location.longitude)
            environment = snapshot
        } catch {
            environment = .placeholder
        }
    }

    func loadCommunityFeed() async {
        communityPosts = await firebaseService.fetchCommunityPosts()
    }

    func authenticateUser(email: String, password: String) async {
        isAuthenticated = await firebaseService.signIn(email: email, password: password)
    }

    func generatePostInsights(for post: CommunityPost) async {
        aiSummary = await appleIntelligenceService.generateInsights(for: post, weather: environment)
    }

    func loadDetections() async {
        let photos = await detectionService.fetchRecentPhotos()
        detectionPhotos = photos
        totalDetections = photos.count
        speciesCounts = photos.reduce(into: [:]) { result, photo in
            let key = photo.species?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let species = key, !species.isEmpty else { return }
            result[species, default: 0] += 1
        }
    }
}
