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

    func generateActionTasks(totalDetections: Int, uniqueSpecies: Int, weather: WeatherSnapshot) async -> [EcoTask] {
        #if canImport(FoundationModels)
        if #available(iOS 18.0, *) {
            let prompt = """
            Create 3 concise wildlife feeder action tasks as JSON array with fields: title, category, priority (1-3).
            Total detections: \(totalDetections)
            Unique species: \(uniqueSpecies)
            Weather: \(weather.condition), humidity \(Int(weather.humidity))%, precipitation \(Int((weather.precipitationChance ?? 0) * 100))%
            """
            do {
                let model = try FoundationModels.LanguageModel.system()
                let response = try await model.generateText(prompt: prompt)
                if let data = response.data(using: .utf8),
                   let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return decoded.compactMap { item in
                        guard let title = item["title"] as? String else { return nil }
                        let category = item["category"] as? String ?? "general"
                        let priority = item["priority"] as? Int ?? 2
                        return EcoTask(title: title, category: category, priority: priority, source: "ai")
                    }
                }
            } catch {
                // fall through
            }
        }
        #endif
        return fallbackTasks(totalDetections: totalDetections, uniqueSpecies: uniqueSpecies, weather: weather)
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

    private func fallbackTasks(totalDetections: Int, uniqueSpecies: Int, weather: WeatherSnapshot) -> [EcoTask] {
        var tasks: [EcoTask] = []
        if weather.isRaining || weather.humidity >= 75 {
            tasks.append(EcoTask(
                title: "Clean and dry the feeder",
                description: "Rain or high humidity can increase spoilage. Sanitize feeding surfaces.",
                category: "cleaning",
                priority: 1,
                source: "ai"
            ))
        }
        if totalDetections > 20 {
            tasks.append(EcoTask(
                title: "Check food levels",
                description: "High traffic detected. Refill if below target.",
                category: "food",
                priority: 2,
                source: "ai"
            ))
        }
        if uniqueSpecies < 3 {
            tasks.append(EcoTask(
                title: "Add a fresh water source",
                description: "A nearby water dish can improve species diversity.",
                category: "habitat",
                priority: 3,
                source: "ai"
            ))
        }
        return tasks
    }
}
