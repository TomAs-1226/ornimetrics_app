import WidgetKit
import SwiftUI

@main
struct OrnimetricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        DetectionStatsWidget()
        DiversityWidget()
        ActivityTimelineWidget()
        TrendsWidget()
        CommunityWidget()
        QuickGlanceWidget()
    }
}