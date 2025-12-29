import WidgetKit
import SwiftUI

// MARK: - Data Model
struct BirdDetectionData: Codable {
    let totalDetections: Int
    let uniqueSpecies: Int
    let lastDetection: String
    let topSpecies: String
    let lastUpdated: Date

    static let placeholder = BirdDetectionData(
        totalDetections: 0,
        uniqueSpecies: 0,
        lastDetection: "No detections yet",
        topSpecies: "—",
        lastUpdated: Date()
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

        // Update every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadData() -> BirdDetectionData {
        let sharedDefaults = UserDefaults(suiteName: "group.com.ornimetrics.app")

        guard let data = sharedDefaults?.data(forKey: "widgetData"),
              let decoded = try? JSONDecoder().decode(BirdDetectionData.self, from: data) else {
            return .placeholder
        }

        return decoded
    }
}

// MARK: - Timeline Entry
struct BirdEntry: TimelineEntry {
    let date: Date
    let data: BirdDetectionData
}

// MARK: - Small Widget View
struct SmallWidgetView: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bird.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Spacer()
                Text("\(entry.data.totalDetections)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Text("Detections")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("\(entry.data.uniqueSpecies) species")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget View
struct MediumWidgetView: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left: Stats
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bird.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    Text("Birds")
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.data.totalDetections)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("detected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.data.uniqueSpecies)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("species")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(minWidth: 100)

            Divider()

            // Right: Recent activity
            VStack(alignment: .leading, spacing: 6) {
                Text("Top Species")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(entry.data.topSpecies)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text(entry.data.lastDetection)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large Widget View
struct LargeWidgetView: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bird.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("Bird Tracker")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Spacer()
                Text("Live")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }

            Divider()

            // Stats Grid
            HStack(spacing: 16) {
                StatCard(
                    icon: "waveform.path.ecg",
                    value: "\(entry.data.totalDetections)",
                    label: "Total Detections",
                    color: .blue
                )

                StatCard(
                    icon: "leaf.fill",
                    value: "\(entry.data.uniqueSpecies)",
                    label: "Unique Species",
                    color: .orange
                )
            }

            Spacer()

            // Top Species
            VStack(alignment: .leading, spacing: 4) {
                Text("Most Detected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                    Text(entry.data.topSpecies)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Footer
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Updated \(entry.data.lastUpdated, style: .relative) ago")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Helper Views
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Widget Configuration
struct OrnimetricsWidget: Widget {
    let kind: String = "OrnimetricsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OrnimetricsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Bird Detections")
        .description("Track your bird detection statistics.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct OrnimetricsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// Note: WidgetBundle is defined in OrnimetricsWidgetBundle.swift

// MARK: - Preview
#Preview(as: .systemSmall) {
    OrnimetricsWidget()
} timeline: {
    BirdEntry(date: .now, data: BirdDetectionData(
        totalDetections: 156,
        uniqueSpecies: 12,
        lastDetection: "Blue Jay",
        topSpecies: "American Robin",
        lastUpdated: Date()
    ))
}

#Preview(as: .systemMedium) {
    OrnimetricsWidget()
} timeline: {
    BirdEntry(date: .now, data: BirdDetectionData(
        totalDetections: 156,
        uniqueSpecies: 12,
        lastDetection: "Blue Jay",
        topSpecies: "American Robin",
        lastUpdated: Date()
    ))
}

#Preview(as: .systemLarge) {
    OrnimetricsWidget()
} timeline: {
    BirdEntry(date: .now, data: BirdDetectionData(
        totalDetections: 156,
        uniqueSpecies: 12,
        lastDetection: "Blue Jay",
        topSpecies: "American Robin",
        lastUpdated: Date()
    ))
}
