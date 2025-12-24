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
            Post: \(post.body)
            Weather: \(weather.condition), \(weather.temperatureC)°C, humidity \(weather.humidity)%.
            Sensor tags: \(post.sensorTags.joined(separator: ", ")).
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

    private func fallbackSummary(for post: CommunityPost, weather: WeatherSnapshot) -> String {
        "Activity logged during \(weather.condition.lowercased()) conditions with humidity near \(weather.humidity)%. Monitor feeder traffic and refill cadence accordingly."
    }
}
