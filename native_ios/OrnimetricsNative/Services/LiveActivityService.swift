import ActivityKit
import Foundation

struct FeederActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
    }

    var name: String
}

final class LiveActivityService {
    func startFeederActivity(progress: Double) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FeederActivityAttributes(name: "Feeder Status")
        let contentState = FeederActivityAttributes.ContentState(progress: progress)
        do {
            _ = try Activity.request(attributes: attributes, contentState: contentState, pushType: nil)
        } catch {
            // ignore
        }
    }

    func stopAll() async {
        for activity in Activity<FeederActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
