import WidgetKit
import SwiftUI

@main
struct OrnimetricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        DetectionCounterWidget()
        SpeciesSpotlightWidget()
        QuickGlanceWidget()
        ActivityRingWidget()
        NatureCardWidget()
        CompactStatsWidget()
    }
}
