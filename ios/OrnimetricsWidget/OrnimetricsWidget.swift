import WidgetKit
import SwiftUI

// MARK: - Data Model
struct BirdDetectionData: Codable {
    let totalDetections: Int
    let uniqueSpecies: Int
    let lastDetection: String
    let topSpecies: String
    let lastUpdated: String

    var lastUpdatedDate: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: lastUpdated) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: lastUpdated) ?? Date()
    }

    static let placeholder = BirdDetectionData(
        totalDetections: 0,
        uniqueSpecies: 0,
        lastDetection: "No detections yet",
        topSpecies: "—",
        lastUpdated: ISO8601DateFormatter().string(from: Date())
    )

    static let sample = BirdDetectionData(
        totalDetections: 156,
        uniqueSpecies: 12,
        lastDetection: "Blue Jay",
        topSpecies: "American Robin",
        lastUpdated: ISO8601DateFormatter().string(from: Date())
    )
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BirdEntry {
        BirdEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BirdEntry) -> ()) {
        let entry = BirdEntry(date: Date(), data: loadData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let data = loadData()
        let entry = BirdEntry(date: currentDate, data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadData() -> BirdDetectionData {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.ornimetrics.app") else {
            return .placeholder
        }

        if let data = sharedDefaults.data(forKey: "widgetData") {
            do {
                return try JSONDecoder().decode(BirdDetectionData.self, from: data)
            } catch {}
        }

        if let jsonString = sharedDefaults.string(forKey: "widgetData"),
           let data = jsonString.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(BirdDetectionData.self, from: data)
            } catch {}
        }

        return .placeholder
    }
}

// MARK: - Timeline Entry
struct BirdEntry: TimelineEntry {
    let date: Date
    let data: BirdDetectionData
}

// MARK: - Color Themes
struct WidgetColors {
    static let primaryGreen = Color(red: 0.2, green: 0.7, blue: 0.4)
    static let accentOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let softBlue = Color(red: 0.3, green: 0.5, blue: 0.9)
    static let warmYellow = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let deepPurple = Color(red: 0.5, green: 0.3, blue: 0.8)
    static let coral = Color(red: 1.0, green: 0.4, blue: 0.4)
}

// ============================================================================
// MARK: - WIDGET 1: Detection Counter (Main Stats)
// ============================================================================

struct DetectionCounterSmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bird.fill")
                    .font(.title2)
                    .foregroundColor(WidgetColors.primaryGreen)
                Spacer()
            }

            Spacer()

            Text("\(entry.data.totalDetections)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.6)

            Text("detections")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.accentOrange)
                Text("\(entry.data.uniqueSpecies) species")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DetectionCounterMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left side - main stats
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bird.fill")
                        .font(.title2)
                        .foregroundColor(WidgetColors.primaryGreen)
                    Text("Bird Tracker")
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.data.totalDetections)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("total detections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Right side - species info
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Species Found")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.data.uniqueSpecies)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentOrange)
                        Text("unique")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Species")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(entry.data.topSpecies)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DetectionCounterLarge: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bird.fill")
                        .font(.title2)
                        .foregroundColor(WidgetColors.primaryGreen)
                    Text("Bird Tracker")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(WidgetColors.primaryGreen)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Main stats
            HStack(spacing: 20) {
                StatCardLarge(
                    icon: "waveform.path.ecg",
                    value: "\(entry.data.totalDetections)",
                    label: "Total Detections",
                    color: WidgetColors.softBlue
                )

                StatCardLarge(
                    icon: "leaf.fill",
                    value: "\(entry.data.uniqueSpecies)",
                    label: "Unique Species",
                    color: WidgetColors.accentOrange
                )
            }

            Spacer()

            // Top species highlight
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Most Detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(WidgetColors.warmYellow)
                        Text(entry.data.topSpecies)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.data.lastDetection)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Footer
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Updated \(entry.data.lastUpdatedDate, style: .relative) ago")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - WIDGET 2: Species Spotlight
// ============================================================================

struct SpeciesSpotlightSmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.title)
                .foregroundColor(WidgetColors.warmYellow)

            Text(entry.data.topSpecies)
                .font(.headline)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("Top Species")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .containerBackground(
            LinearGradient(
                colors: [WidgetColors.warmYellow.opacity(0.2), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            ),
            for: .widget
        )
    }
}

struct SpeciesSpotlightMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 16) {
            // Crown icon with glow effect
            ZStack {
                Circle()
                    .fill(WidgetColors.warmYellow.opacity(0.2))
                    .frame(width: 70, height: 70)
                Image(systemName: "crown.fill")
                    .font(.system(size: 32))
                    .foregroundColor(WidgetColors.warmYellow)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TOP SPECIES")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(WidgetColors.warmYellow)

                Text(entry.data.topSpecies)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.caption2)
                        Text("1 of \(entry.data.uniqueSpecies)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(
            LinearGradient(
                colors: [WidgetColors.warmYellow.opacity(0.15), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }
}

// ============================================================================
// MARK: - WIDGET 3: Quick Glance (Minimal)
// ============================================================================

struct QuickGlanceSmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(spacing: 4) {
            Spacer()

            Text("\(entry.data.totalDetections)")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WidgetColors.primaryGreen, WidgetColors.softBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 4) {
                Image(systemName: "bird.fill")
                    .font(.caption)
                Text("birds")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct QuickGlanceMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 0) {
            // Detections
            VStack(spacing: 4) {
                Text("\(entry.data.totalDetections)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [WidgetColors.primaryGreen, WidgetColors.softBlue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("detections")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
                .padding(.vertical, 20)

            // Species
            VStack(spacing: 4) {
                Text("\(entry.data.uniqueSpecies)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [WidgetColors.accentOrange, WidgetColors.coral],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("species")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - WIDGET 4: Activity Ring
// ============================================================================

struct ActivityRingSmall: View {
    let entry: BirdEntry

    var progress: Double {
        min(Double(entry.data.totalDetections) / 100.0, 1.0)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(WidgetColors.primaryGreen.opacity(0.2), lineWidth: 12)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [WidgetColors.primaryGreen, WidgetColors.softBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 2) {
                Text("\(entry.data.totalDetections)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Image(systemName: "bird.fill")
                    .font(.caption)
                    .foregroundColor(WidgetColors.primaryGreen)
            }
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ActivityRingMedium: View {
    let entry: BirdEntry

    var detectionProgress: Double {
        min(Double(entry.data.totalDetections) / 100.0, 1.0)
    }

    var speciesProgress: Double {
        min(Double(entry.data.uniqueSpecies) / 20.0, 1.0)
    }

    var body: some View {
        HStack(spacing: 20) {
            // Rings
            ZStack {
                // Outer ring (detections)
                Circle()
                    .stroke(WidgetColors.primaryGreen.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: detectionProgress)
                    .stroke(WidgetColors.primaryGreen, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Inner ring (species)
                Circle()
                    .stroke(WidgetColors.accentOrange.opacity(0.2), lineWidth: 10)
                    .padding(14)
                Circle()
                    .trim(from: 0, to: speciesProgress)
                    .stroke(WidgetColors.accentOrange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(14)

                Image(systemName: "bird.fill")
                    .font(.title2)
                    .foregroundColor(WidgetColors.primaryGreen)
            }
            .frame(width: 90, height: 90)

            // Stats
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(WidgetColors.primaryGreen)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text("\(entry.data.totalDetections)")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Detections")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(WidgetColors.accentOrange)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text("\(entry.data.uniqueSpecies)")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Species")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - WIDGET 5: Nature Card (Photo Style)
// ============================================================================

struct NatureCardSmall: View {
    let entry: BirdEntry

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.4, blue: 0.3),
                    Color(red: 0.2, green: 0.5, blue: 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "leaf.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }

                Spacer()

                Text(entry.data.topSpecies)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text("\(entry.data.totalDetections) detections")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct NatureCardMedium: View {
    let entry: BirdEntry

    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.35, blue: 0.3),
                    Color(red: 0.15, green: 0.45, blue: 0.35),
                    Color(red: 0.2, green: 0.5, blue: 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.circle.fill")
                            .font(.title2)
                        Text("Ornimetrics")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white.opacity(0.95))

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.data.topSpecies)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        HStack(spacing: 16) {
                            Label("\(entry.data.totalDetections)", systemImage: "waveform")
                            Label("\(entry.data.uniqueSpecies)", systemImage: "leaf.fill")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                // Decorative bird silhouette
                Image(systemName: "bird.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.15))
            }
            .padding()
        }
        .containerBackground(.clear, for: .widget)
    }
}

// ============================================================================
// MARK: - WIDGET 6: Compact Stats Bar
// ============================================================================

struct CompactStatsSmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "bird.fill")
                    .foregroundColor(WidgetColors.primaryGreen)
                Spacer()
                Text("Today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 8) {
                HStack {
                    Text("Detections")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(entry.data.totalDetections)")
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Divider()

                HStack {
                    Text("Species")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(entry.data.uniqueSpecies)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(WidgetColors.accentOrange)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - Helper Views
// ============================================================================

struct StatCardLarge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// ============================================================================
// MARK: - Widget Configurations
// ============================================================================

// Widget 1: Detection Counter
struct DetectionCounterWidget: Widget {
    let kind: String = "DetectionCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DetectionCounterView(entry: entry)
        }
        .configurationDisplayName("Detection Counter")
        .description("Track your total bird detections and species count.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DetectionCounterView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            DetectionCounterSmall(entry: entry)
        case .systemMedium:
            DetectionCounterMedium(entry: entry)
        case .systemLarge:
            DetectionCounterLarge(entry: entry)
        default:
            DetectionCounterSmall(entry: entry)
        }
    }
}

// Widget 2: Species Spotlight
struct SpeciesSpotlightWidget: Widget {
    let kind: String = "SpeciesSpotlightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SpeciesSpotlightView(entry: entry)
        }
        .configurationDisplayName("Species Spotlight")
        .description("Highlight your most detected bird species.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SpeciesSpotlightView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SpeciesSpotlightSmall(entry: entry)
        case .systemMedium:
            SpeciesSpotlightMedium(entry: entry)
        default:
            SpeciesSpotlightSmall(entry: entry)
        }
    }
}

// Widget 3: Quick Glance
struct QuickGlanceWidget: Widget {
    let kind: String = "QuickGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QuickGlanceView(entry: entry)
        }
        .configurationDisplayName("Quick Glance")
        .description("Minimal view of your bird detection stats.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickGlanceView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            QuickGlanceSmall(entry: entry)
        case .systemMedium:
            QuickGlanceMedium(entry: entry)
        default:
            QuickGlanceSmall(entry: entry)
        }
    }
}

// Widget 4: Activity Ring
struct ActivityRingWidget: Widget {
    let kind: String = "ActivityRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ActivityRingView(entry: entry)
        }
        .configurationDisplayName("Activity Rings")
        .description("Visual progress rings for detections and species.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ActivityRingView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            ActivityRingSmall(entry: entry)
        case .systemMedium:
            ActivityRingMedium(entry: entry)
        default:
            ActivityRingSmall(entry: entry)
        }
    }
}

// Widget 5: Nature Card
struct NatureCardWidget: Widget {
    let kind: String = "NatureCardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NatureCardView(entry: entry)
        }
        .configurationDisplayName("Nature Card")
        .description("Beautiful nature-themed stats display.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NatureCardView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            NatureCardSmall(entry: entry)
        case .systemMedium:
            NatureCardMedium(entry: entry)
        default:
            NatureCardSmall(entry: entry)
        }
    }
}

// Widget 6: Compact Stats
struct CompactStatsWidget: Widget {
    let kind: String = "CompactStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CompactStatsSmall(entry: entry)
        }
        .configurationDisplayName("Compact Stats")
        .description("Clean, compact view of your stats.")
        .supportedFamilies([.systemSmall])
    }
}

// ============================================================================
// MARK: - Previews
// ============================================================================

#Preview("Counter Small", as: .systemSmall) {
    DetectionCounterWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Counter Medium", as: .systemMedium) {
    DetectionCounterWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Counter Large", as: .systemLarge) {
    DetectionCounterWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Spotlight Small", as: .systemSmall) {
    SpeciesSpotlightWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Spotlight Medium", as: .systemMedium) {
    SpeciesSpotlightWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Quick Glance Small", as: .systemSmall) {
    QuickGlanceWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Quick Glance Medium", as: .systemMedium) {
    QuickGlanceWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Activity Ring Small", as: .systemSmall) {
    ActivityRingWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Activity Ring Medium", as: .systemMedium) {
    ActivityRingWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Nature Card Small", as: .systemSmall) {
    NatureCardWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Nature Card Medium", as: .systemMedium) {
    NatureCardWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}

#Preview("Compact Stats", as: .systemSmall) {
    CompactStatsWidget()
} timeline: {
    BirdEntry(date: .now, data: .sample)
}
