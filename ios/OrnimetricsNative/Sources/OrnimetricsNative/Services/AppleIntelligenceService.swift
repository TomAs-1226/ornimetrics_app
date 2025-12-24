import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleIntelligenceService {
    func generateInsights(for post: CommunityPost, weather: WeatherSnapshot) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 18.0, *) {
            let prompt = """
            Provide a concise ecology insight based on this community post.
            Post: \(post.caption)
            Weather: \(weather.condition), \(weather.temperatureC)°C, humidity \(weather.humidity)%.
            Sensor tags: low food \(post.sensors.lowFood), clogged \(post.sensors.clogged), cleaning due \(post.sensors.cleaningDue).
            """
            do {
                let model = try FoundationModels.LanguageModel.system()
                let response = try await model.generateText(prompt: prompt)
                return response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return fallbackSummary(for: post, weather: weather)
            }
        }
        #endif
        return fallbackSummary(for: post, weather: weather)
    }

    func generateDashboardSummary(totalDetections: Int, uniqueSpecies: Int, weather: WeatherSnapshot) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 18.0, *) {
            let prompt = """
            Summarize the latest wildlife dashboard in two sentences.
            Total detections: \(totalDetections).
            Unique species: \(uniqueSpecies).
            Weather: \(weather.condition), \(Int(weather.temperatureC))°C, humidity \(Int(weather.humidity))%.
            Highlight one action to keep the feeder safe.
            """
            do {
                let model = try FoundationModels.LanguageModel.system()
                let response = try await model.generateText(prompt: prompt)
                return response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return fallbackDashboardSummary(totalDetections: totalDetections, uniqueSpecies: uniqueSpecies, weather: weather)
            }
        }
        #endif
        return fallbackDashboardSummary(totalDetections: totalDetections, uniqueSpecies: uniqueSpecies, weather: weather)
    }

    func generateReply(userMessage: String, post: CommunityPost, weather: WeatherSnapshot?) async -> String {
        let weatherSummary = weather.map { "\($0.condition), \($0.temperatureC)°C, humidity \($0.humidity)%" } ?? "No weather snapshot"
        #if canImport(FoundationModels)
        if #available(iOS 18.0, *) {
            let prompt = """
            You are an avian behavior guide. Reply concisely with safe, practical advice.
            Post caption: \(post.caption).
            Time of day: \(post.timeOfDayTag).
            Sensors: food low \(post.sensors.lowFood), clogged \(post.sensors.clogged), cleaning due \(post.sensors.cleaningDue).
            Weather: \(weatherSummary).
            User question: \(userMessage)
            """
            do {
                let model = try FoundationModels.LanguageModel.system()
                let response = try await model.generateText(prompt: prompt)
                return response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return fallbackReply()
            }
        }
        #endif
        return fallbackReply()
    }

    private func fallbackSummary(for post: CommunityPost, weather: WeatherSnapshot) -> String {
        "Activity logged during \(weather.condition.lowercased()) conditions with humidity near \(weather.humidity)%. Monitor feeder traffic and refill cadence accordingly."
    }

    private func fallbackDashboardSummary(totalDetections: Int, uniqueSpecies: Int, weather: WeatherSnapshot) -> String {
        "You logged \(totalDetections) detections across \(uniqueSpecies) species. With \(weather.condition.lowercased()) weather, keep the feeder clean and check food levels regularly."
    }

    private func fallbackReply() -> String {
        "That sighting sounds healthy for local wildlife. Monitor feeder cleanliness and ensure fresh food and water, especially during active hours."
    }
}
