import SwiftUI
import Combine

final class OrnimetricsAppState: ObservableObject {
    @Published var config = AppConfig()
    @Published var isFaceIDUnlocked = false
    @Published var weatherSnapshot: WeatherSnapshot?
    @Published var feederProgress: Double = 0.68
    @Published var notificationsEnabled = true
    @Published var liveActivityEnabled = false

    private let firebaseService = FirebaseService()
    private let weatherService = WeatherKitService()
    private let locationService = LocationService()
    private let faceIDService = FaceIDService()
    private let liveActivityService = LiveActivityService()

    func bootstrap() {
        config.load()
        firebaseService.configure(with: config)
        locationService.requestAuthorization()
        Task { @MainActor in
            await refreshWeather()
        }
    }

    @MainActor
    func refreshWeather() async {
        do {
            let location = try await locationService.currentLocation()
            let snapshot = try await weatherService.fetchWeather(for: location)
            withAnimation(.spring()) {
                weatherSnapshot = snapshot
            }
        } catch {
            weatherSnapshot = WeatherSnapshot.placeholder
        }
    }

    @MainActor
    func toggleFaceID() async {
        do {
            let success = try await faceIDService.authenticate()
            withAnimation(.easeInOut) {
                isFaceIDUnlocked = success
            }
        } catch {
            isFaceIDUnlocked = false
        }
    }

    @MainActor
    func toggleLiveActivity() async {
        liveActivityEnabled.toggle()
        if liveActivityEnabled {
            await liveActivityService.startFeederActivity(progress: feederProgress)
        } else {
            await liveActivityService.stopAll()
        }
    }
}
