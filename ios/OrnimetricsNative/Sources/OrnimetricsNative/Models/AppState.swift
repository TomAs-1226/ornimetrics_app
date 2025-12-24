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
    @Published var lastUpdated: Date?
    @Published var tasks: [EcoTask] = []
    @Published var trendSignals: [TrendSignal] = []
    @Published var trendRollup: TrendRollup = TrendRollup(recentTotal: 0, priorTotal: 0, busiestDayKey: nil, busiestDayTotal: 0)
    @Published var aiAnalysis: String = ""
    @Published var accentColorHex: String = "#2ECC71"

    let config: AppConfig
    let weatherService: WeatherService
    let firebaseService: FirebaseService
    let appleIntelligenceService: AppleIntelligenceService
    let detectionService: DetectionService
    let notificationsCenter: NotificationsCenter
    private var autoRefreshTimer: Timer?

    init(config: AppConfig) {
        self.config = config
        self.weatherService = WeatherService(config: config)
        self.firebaseService = FirebaseService(config: config)
        self.appleIntelligenceService = AppleIntelligenceService()
        self.detectionService = DetectionService(config: config)
        self.notificationsCenter = NotificationsCenter()
        self.accentColorHex = UserDefaults.standard.string(forKey: "pref_seed_color_hex") ?? "#2ECC71"
        loadTasks()
    }

    func bootstrap() async {
        await refreshAll()
        notificationsCenter.startFoodLevelTracking()
        configureAutoRefresh()
    }

    func refreshEnvironment() async {
        do {
            let snapshot = try await weatherService.fetchCurrentWeather(latitude: feederStatus.location.latitude,
                                                                        longitude: feederStatus.location.longitude)
            environment = snapshot
            MaintenanceRulesEngine.evaluateWeather(snapshot, preferences: notificationsCenter.preferences, notifications: notificationsCenter)
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
        lastUpdated = Date()
        updateTrends(from: photos)
    }

    func refreshAll() async {
        await refreshEnvironment()
        await loadCommunityFeed()
        await loadDetections()
        notificationsCenter.triggerCleaningCheck()
        ensureCleaningTaskIfNeeded()
        await generateAiAnalysis()
    }

    func generateAiAnalysis() async {
        let summary = await appleIntelligenceService.generateDashboardSummary(
            totalDetections: totalDetections,
            uniqueSpecies: speciesCounts.count,
            weather: environment
        )
        aiAnalysis = summary
    }

    func addTask(_ task: EcoTask) {
        tasks.append(task)
        saveTasks()
    }

    func toggleTask(_ task: EcoTask, done: Bool) {
        guard let index = tasks.firstIndex(of: task) else { return }
        tasks[index].done = done
        saveTasks()
    }

    func updateAccentColor(hex: String) {
        accentColorHex = hex
        UserDefaults.standard.set(hex, forKey: "pref_seed_color_hex")
    }

    func configureAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        let enabled = UserDefaults.standard.bool(forKey: "pref_auto_refresh_enabled")
        let interval = UserDefaults.standard.double(forKey: "pref_auto_refresh_interval")
        guard enabled else { return }
        let seconds = interval == 0 ? 60 : interval
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    private func updateTrends(from photos: [DetectionPhoto]) {
        let calendar = Calendar.current
        let now = Date()
        let recentStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let priorStart = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let recent = photos.filter { $0.timestamp >= recentStart }
        let prior = photos.filter { $0.timestamp < recentStart && $0.timestamp >= priorStart }

        func counts(_ items: [DetectionPhoto]) -> [String: Int] {
            items.reduce(into: [:]) { result, photo in
                guard let species = photo.species, !species.isEmpty else { return }
                result[species, default: 0] += 1
            }
        }

        let recentCounts = counts(recent)
        let priorCounts = counts(prior)
        let allSpecies = Set(recentCounts.keys).union(priorCounts.keys)

        trendSignals = allSpecies.map { species in
            TrendSignal(species: species, start: priorCounts[species] ?? 0, end: recentCounts[species] ?? 0)
        }
        .sorted { abs($0.delta) > abs($1.delta) }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d"
        var dailyCounts: [String: Int] = [:]
        for photo in recent {
            let key = dayFormatter.string(from: photo.timestamp)
            dailyCounts[key, default: 0] += 1
        }
        let busiest = dailyCounts.max { $0.value < $1.value }
        trendRollup = TrendRollup(
            recentTotal: recent.count,
            priorTotal: prior.count,
            busiestDayKey: busiest?.key,
            busiestDayTotal: busiest?.value ?? 0
        )
    }

    private func ensureCleaningTaskIfNeeded() {
        let prefs = notificationsCenter.preferences
        let last = prefs.lastCleaned
        let interval = prefs.cleaningIntervalDays
        let daysSince = last == nil ? interval + 1 : Calendar.current.dateComponents([.day], from: last!, to: Date()).day ?? interval + 1
        guard daysSince >= interval else { return }
        if tasks.contains(where: { $0.category == "cleaning" && !$0.done }) {
            return
        }
        let task = EcoTask(
            title: "Clean the feeder",
            description: "It's been \(daysSince) day(s) since the last cleaning. Sanitize to reduce disease spread.",
            category: "cleaning",
            priority: 1,
            dueAt: Date().addingTimeInterval(86400),
            source: "system"
        )
        tasks.append(task)
        saveTasks()
    }

    private func loadTasks() {
        guard let data = UserDefaults.standard.data(forKey: "ornimetrics.tasks"),
              let decoded = try? JSONDecoder().decode([EcoTask].self, from: data) else {
            tasks = []
            return
        }
        tasks = decoded
    }

    private func saveTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: "ornimetrics.tasks")
    }
}
