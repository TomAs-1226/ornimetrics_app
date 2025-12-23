import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var feederStatus = FeederStatus.sample
    @Published var environment = WeatherSnapshot.placeholder
    @Published var communityPosts: [CommunityPost] = []
    @Published var isAuthenticated = false
    @Published var aiSummary: String = ""

    let config: AppConfig
    let weatherService: WeatherService
    let firebaseService: FirebaseService
    let appleIntelligenceService: AppleIntelligenceService

    init(config: AppConfig) {
        self.config = config
        self.weatherService = WeatherService(config: config)
        self.firebaseService = FirebaseService(config: config)
        self.appleIntelligenceService = AppleIntelligenceService()
    }

    func bootstrap() async {
        await refreshEnvironment()
        await loadCommunityFeed()
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
}
