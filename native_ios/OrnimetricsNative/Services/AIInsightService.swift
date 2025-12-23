import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIInsightService {
    func generateInsight(from text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 18.0, *) {
            let model = SystemModel()
            let response = try await model.generateText(from: "Summarize this observation for a community post: \(text)")
            return response.text
        }
        #endif
        return "On-device AI is unavailable; please check Apple Intelligence setup."
    }
}
