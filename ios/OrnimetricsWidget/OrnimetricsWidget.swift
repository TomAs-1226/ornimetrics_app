import WidgetKit
import SwiftUI

// MARK: - Data Model
struct BirdDetectionData: Codable {
    // Core stats
    let totalDetections: Int
    let uniqueSpecies: Int
    let lastDetection: String
    let topSpecies: String
    let lastUpdated: String

    // Diversity metrics
    let rarityScore: Double          // 0-100, higher = more rare species
    let diversityIndex: Double       // Shannon diversity index
    let commonSpeciesRatio: Double   // % of detections that are common species

    // Activity metrics
    let hourlyActivity: [Int]        // 24 values for each hour
    let peakHour: Int                // Hour with most activity (0-23)
    let activeHours: Int             // Number of hours with detections

    // Trends
    let weeklyTrend: Double          // % change from last week
    let monthlyTrend: Double         // % change from last month
    let trendingSpecies: String      // Species with biggest increase
    let decliningSpecies: String     // Species with biggest decrease

    // Community
    let communityTotal: Int          // Total community detections
    let userRank: Int                // User's rank in community
    let communityMembers: Int        // Active community members
    let sharedSightings: Int         // Sightings shared this week

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
        lastDetection: "No detections",
        topSpecies: "—",
        lastUpdated: ISO8601DateFormatter().string(from: Date()),
        rarityScore: 0,
        diversityIndex: 0,
        commonSpeciesRatio: 0,
        hourlyActivity: Array(repeating: 0, count: 24),
        peakHour: 12,
        activeHours: 0,
        weeklyTrend: 0,
        monthlyTrend: 0,
        trendingSpecies: "—",
        decliningSpecies: "—",
        communityTotal: 0,
        userRank: 0,
        communityMembers: 0,
        sharedSightings: 0
    )

    static let sample = BirdDetectionData(
        totalDetections: 156,
        uniqueSpecies: 12,
        lastDetection: "Blue Jay",
        topSpecies: "American Robin",
        lastUpdated: ISO8601DateFormatter().string(from: Date()),
        rarityScore: 72,
        diversityIndex: 2.4,
        commonSpeciesRatio: 0.65,
        hourlyActivity: [0,0,0,0,0,2,8,15,22,18,12,8,10,14,16,12,8,5,3,1,0,0,0,0],
        peakHour: 8,
        activeHours: 16,
        weeklyTrend: 12.5,
        monthlyTrend: -3.2,
        trendingSpecies: "Cedar Waxwing",
        decliningSpecies: "House Sparrow",
        communityTotal: 4520,
        userRank: 23,
        communityMembers: 156,
        sharedSightings: 8
    )
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BirdEntry {
        BirdEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BirdEntry) -> ()) {
        completion(BirdEntry(date: Date(), data: loadData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = BirdEntry(date: Date(), data: loadData())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadData() -> BirdDetectionData {
        guard let defaults = UserDefaults(suiteName: "group.com.ornimetrics.app"),
              let data = defaults.data(forKey: "widgetData") ?? defaults.string(forKey: "widgetData")?.data(using: .utf8),
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

// MARK: - Color Themes
struct WidgetColors {
    static let primaryGreen = Color(red: 0.2, green: 0.7, blue: 0.4)
    static let accentOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let softBlue = Color(red: 0.3, green: 0.5, blue: 0.9)
    static let warmYellow = Color(red: 1.0, green: 0.8, blue: 0.2)
    static let deepPurple = Color(red: 0.5, green: 0.3, blue: 0.8)
    static let coral = Color(red: 1.0, green: 0.4, blue: 0.4)
    static let teal = Color(red: 0.2, green: 0.6, blue: 0.7)
    static let mint = Color(red: 0.4, green: 0.8, blue: 0.7)
}

// ============================================================================
// MARK: - WIDGET 1: Detection Stats (Core metrics)
// ============================================================================

struct DetectionStatsSmall: View {
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

struct DetectionStatsMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 16) {
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

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Species")
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

struct DetectionStatsLarge: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    Circle().fill(WidgetColors.primaryGreen).frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack(spacing: 20) {
                StatBox(icon: "waveform.path.ecg", value: "\(entry.data.totalDetections)", label: "Detections", color: WidgetColors.softBlue)
                StatBox(icon: "leaf.fill", value: "\(entry.data.uniqueSpecies)", label: "Species", color: WidgetColors.accentOrange)
            }

            Spacer()

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

            HStack {
                Image(systemName: "clock").font(.caption2)
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
// MARK: - WIDGET 2: Species Diversity
// ============================================================================

struct DiversitySmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(WidgetColors.deepPurple.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: entry.data.rarityScore / 100)
                    .stroke(WidgetColors.deepPurple, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(entry.data.rarityScore))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("rarity")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            Text("Diversity Score")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .containerBackground(
            LinearGradient(colors: [WidgetColors.deepPurple.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom),
            for: .widget
        )
    }
}

struct DiversityMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 16) {
            // Rarity ring
            ZStack {
                Circle()
                    .stroke(WidgetColors.deepPurple.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.data.rarityScore / 100)
                    .stroke(
                        LinearGradient(colors: [WidgetColors.deepPurple, WidgetColors.coral], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(entry.data.rarityScore))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("rarity")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(WidgetColors.deepPurple)
                    Text("Diversity")
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 6) {
                    DiversityRow(label: "Shannon Index", value: String(format: "%.2f", entry.data.diversityIndex), color: WidgetColors.teal)
                    DiversityRow(label: "Common Ratio", value: "\(Int(entry.data.commonSpeciesRatio * 100))%", color: WidgetColors.accentOrange)
                    DiversityRow(label: "Unique Species", value: "\(entry.data.uniqueSpecies)", color: WidgetColors.primaryGreen)
                }
            }
            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DiversityLarge: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(WidgetColors.deepPurple)
                Text("Species Diversity")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                // Large rarity ring
                ZStack {
                    Circle()
                        .stroke(WidgetColors.deepPurple.opacity(0.2), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: entry.data.rarityScore / 100)
                        .stroke(
                            LinearGradient(colors: [WidgetColors.deepPurple, WidgetColors.coral], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(entry.data.rarityScore))")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Rarity Score")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    MetricCard(icon: "function", title: "Shannon Index", value: String(format: "%.2f", entry.data.diversityIndex), subtitle: "Biodiversity measure", color: WidgetColors.teal)
                    MetricCard(icon: "chart.pie.fill", title: "Common Ratio", value: "\(Int(entry.data.commonSpeciesRatio * 100))%", subtitle: "Common species", color: WidgetColors.accentOrange)
                }
            }

            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unique Species Found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(entry.data.uniqueSpecies)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(WidgetColors.primaryGreen)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Top Discovery")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.data.topSpecies)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(WidgetColors.deepPurple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - WIDGET 3: Activity Timeline
// ============================================================================

struct ActivityTimelineSmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(WidgetColors.softBlue)
                Spacer()
                Text("Peak: \(formatHour(entry.data.peakHour))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Mini activity bars
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let height = barHeight(for: hour)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(hour == entry.data.peakHour ? WidgetColors.softBlue : WidgetColors.softBlue.opacity(0.4))
                        .frame(width: 4, height: max(4, height * 40))
                }
            }
            .frame(height: 40)

            Text("\(entry.data.activeHours)h active")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func barHeight(for hour: Int) -> CGFloat {
        let max = entry.data.hourlyActivity.max() ?? 1
        guard max > 0 else { return 0 }
        return CGFloat(entry.data.hourlyActivity[hour]) / CGFloat(max)
    }

    func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12AM" }
        if hour == 12 { return "12PM" }
        return hour < 12 ? "\(hour)AM" : "\(hour-12)PM"
    }
}

struct ActivityTimelineMedium: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(WidgetColors.softBlue)
                    Text("Activity Timeline")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text("Peak: \(formatHour(entry.data.peakHour))")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WidgetColors.softBlue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Spacer()

            // Activity bars with labels
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                hour == entry.data.peakHour
                                    ? LinearGradient(colors: [WidgetColors.softBlue, WidgetColors.teal], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [WidgetColors.softBlue.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 8, height: max(4, barHeight(for: hour) * 50))
                        if hour % 6 == 0 {
                            Text("\(hour)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(height: 65)

            HStack {
                Label("\(entry.data.activeHours) active hours", systemImage: "sun.max.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Label("\(entry.data.totalDetections) total", systemImage: "bird.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func barHeight(for hour: Int) -> CGFloat {
        let max = entry.data.hourlyActivity.max() ?? 1
        guard max > 0 else { return 0 }
        return CGFloat(entry.data.hourlyActivity[hour]) / CGFloat(max)
    }

    func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12AM" }
        if hour == 12 { return "12PM" }
        return hour < 12 ? "\(hour)AM" : "\(hour-12)PM"
    }
}

// ============================================================================
// MARK: - WIDGET 4: Migration & Trends
// ============================================================================

struct TrendsSmall: View {
    let entry: BirdEntry

    var trendColor: Color {
        entry.data.weeklyTrend >= 0 ? WidgetColors.primaryGreen : WidgetColors.coral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(trendColor)
                Spacer()
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: entry.data.weeklyTrend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                Text("\(abs(Int(entry.data.weeklyTrend)))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            .foregroundColor(trendColor)

            Text("vs last week")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(entry.data.trendingSpecies)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TrendsMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 16) {
            // Weekly trend
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(WidgetColors.teal)
                    Text("Trends")
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                Spacer()

                TrendIndicator(label: "Weekly", value: entry.data.weeklyTrend)
                TrendIndicator(label: "Monthly", value: entry.data.monthlyTrend)
            }

            Divider()

            // Trending species
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(WidgetColors.primaryGreen)
                        Text("Trending")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(entry.data.trendingSpecies)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(WidgetColors.coral)
                        Text("Declining")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(entry.data.decliningSpecies)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TrendsLarge: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(WidgetColors.teal)
                Text("Migration & Trends")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                TrendCard(title: "This Week", value: entry.data.weeklyTrend, icon: "calendar")
                TrendCard(title: "This Month", value: entry.data.monthlyTrend, icon: "calendar.badge.clock")
            }

            Spacer()

            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(WidgetColors.primaryGreen)
                        VStack(alignment: .leading) {
                            Text("Trending Up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.data.trendingSpecies)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(WidgetColors.primaryGreen.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundColor(WidgetColors.coral)
                        VStack(alignment: .leading) {
                            Text("Declining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.data.decliningSpecies)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(WidgetColors.coral.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - WIDGET 5: Community Hub
// ============================================================================

struct CommunitySmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(WidgetColors.accentOrange)
                Spacer()
            }

            Spacer()

            Text("#\(entry.data.userRank)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(WidgetColors.accentOrange)

            Text("Your Rank")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("of \(entry.data.communityMembers) birders")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(
            LinearGradient(colors: [WidgetColors.accentOrange.opacity(0.15), .clear], startPoint: .topTrailing, endPoint: .bottomLeading),
            for: .widget
        )
    }
}

struct CommunityMedium: View {
    let entry: BirdEntry

    var body: some View {
        HStack(spacing: 16) {
            // Rank display
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(WidgetColors.accentOrange.opacity(0.2))
                        .frame(width: 70, height: 70)
                    VStack(spacing: 0) {
                        Text("#\(entry.data.userRank)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.accentOrange)
                    }
                }
                Text("Your Rank")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(WidgetColors.accentOrange)
                    Text("Community")
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 6) {
                    CommunityRow(icon: "bird.fill", label: "Total Sightings", value: formatNumber(entry.data.communityTotal))
                    CommunityRow(icon: "person.2.fill", label: "Active Members", value: "\(entry.data.communityMembers)")
                    CommunityRow(icon: "square.and.arrow.up.fill", label: "Your Shares", value: "\(entry.data.sharedSightings)")
                }
            }
            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func formatNumber(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fK", Double(n)/1000) }
        return "\(n)"
    }
}

struct CommunityLarge: View {
    let entry: BirdEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundColor(WidgetColors.accentOrange)
                Text("Community Hub")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text("\(entry.data.communityMembers) birders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                // Your stats
                VStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [WidgetColors.accentOrange, WidgetColors.warmYellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 80, height: 80)
                        VStack(spacing: 0) {
                            Text("#\(entry.data.userRank)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    Text("Your Rank")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 100)

                VStack(alignment: .leading, spacing: 8) {
                    CommunityStatRow(icon: "bird.fill", title: "Community Total", value: formatNumber(entry.data.communityTotal), color: WidgetColors.primaryGreen)
                    CommunityStatRow(icon: "square.and.arrow.up.fill", title: "Your Shares", value: "\(entry.data.sharedSightings)", color: WidgetColors.softBlue)
                    CommunityStatRow(icon: "star.fill", title: "Your Detections", value: "\(entry.data.totalDetections)", color: WidgetColors.warmYellow)
                }
            }

            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Contributor Species")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.data.topSpecies)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(WidgetColors.accentOrange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func formatNumber(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fK", Double(n)/1000) }
        return "\(n)"
    }
}

// ============================================================================
// MARK: - WIDGET 6: Quick Glance (Minimal)
// ============================================================================

struct QuickGlanceSmall: View {
    let entry: BirdEntry

    var body: some View {
        VStack(spacing: 4) {
            Spacer()
            Text("\(entry.data.totalDetections)")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [WidgetColors.primaryGreen, WidgetColors.softBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            HStack(spacing: 4) {
                Image(systemName: "bird.fill").font(.caption)
                Text("birds").font(.caption).fontWeight(.medium)
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
            VStack(spacing: 4) {
                Text("\(entry.data.totalDetections)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [WidgetColors.primaryGreen, WidgetColors.softBlue], startPoint: .top, endPoint: .bottom)
                    )
                Text("detections").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1).padding(.vertical, 20)

            VStack(spacing: 4) {
                Text("\(entry.data.uniqueSpecies)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [WidgetColors.accentOrange, WidgetColors.coral], startPoint: .top, endPoint: .bottom)
                    )
                Text("species").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ============================================================================
// MARK: - Helper Views
// ============================================================================

struct StatBox: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundColor(color)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DiversityRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold)
        }
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline).fontWeight(.bold)
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct TrendIndicator: View {
    let label: String
    let value: Double

    var color: Color { value >= 0 ? WidgetColors.primaryGreen : WidgetColors.coral }

    var body: some View {
        HStack {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 2) {
                Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                Text("\(abs(Int(value)))%")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(color)
        }
    }
}

struct TrendCard: View {
    let title: String
    let value: Double
    let icon: String

    var color: Color { value >= 0 ? WidgetColors.primaryGreen : WidgetColors.coral }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(WidgetColors.teal)
                Spacer()
            }
            HStack(spacing: 4) {
                Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(Int(value)))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .foregroundColor(color)
            Text(title).font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CommunityRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon).font(.caption2).foregroundColor(.secondary).frame(width: 16)
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold)
        }
    }
}

struct CommunityStatRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 20)
            Text(title).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.semibold)
        }
    }
}

// ============================================================================
// MARK: - Widget Configurations
// ============================================================================

struct DetectionStatsWidget: Widget {
    let kind = "DetectionStatsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DetectionStatsView(entry: entry)
        }
        .configurationDisplayName("Detection Stats")
        .description("Your bird detection count and species.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DetectionStatsView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    var body: some View {
        switch family {
        case .systemSmall: DetectionStatsSmall(entry: entry)
        case .systemMedium: DetectionStatsMedium(entry: entry)
        case .systemLarge: DetectionStatsLarge(entry: entry)
        default: DetectionStatsSmall(entry: entry)
        }
    }
}

struct DiversityWidget: Widget {
    let kind = "DiversityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DiversityView(entry: entry)
        }
        .configurationDisplayName("Species Diversity")
        .description("Biodiversity metrics and rarity scores.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DiversityView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    var body: some View {
        switch family {
        case .systemSmall: DiversitySmall(entry: entry)
        case .systemMedium: DiversityMedium(entry: entry)
        case .systemLarge: DiversityLarge(entry: entry)
        default: DiversitySmall(entry: entry)
        }
    }
}

struct ActivityTimelineWidget: Widget {
    let kind = "ActivityTimelineWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ActivityTimelineView(entry: entry)
        }
        .configurationDisplayName("Activity Timeline")
        .description("Hourly bird activity patterns.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ActivityTimelineView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    var body: some View {
        switch family {
        case .systemSmall: ActivityTimelineSmall(entry: entry)
        case .systemMedium: ActivityTimelineMedium(entry: entry)
        default: ActivityTimelineSmall(entry: entry)
        }
    }
}

struct TrendsWidget: Widget {
    let kind = "TrendsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TrendsView(entry: entry)
        }
        .configurationDisplayName("Migration & Trends")
        .description("Weekly trends and species movements.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TrendsView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    var body: some View {
        switch family {
        case .systemSmall: TrendsSmall(entry: entry)
        case .systemMedium: TrendsMedium(entry: entry)
        case .systemLarge: TrendsLarge(entry: entry)
        default: TrendsSmall(entry: entry)
        }
    }
}

struct CommunityWidget: Widget {
    let kind = "CommunityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CommunityView(entry: entry)
        }
        .configurationDisplayName("Community Hub")
        .description("Your rank and community stats.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CommunityView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    var body: some View {
        switch family {
        case .systemSmall: CommunitySmall(entry: entry)
        case .systemMedium: CommunityMedium(entry: entry)
        case .systemLarge: CommunityLarge(entry: entry)
        default: CommunitySmall(entry: entry)
        }
    }
}

struct QuickGlanceWidget: Widget {
    let kind = "QuickGlanceWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QuickGlanceView(entry: entry)
        }
        .configurationDisplayName("Quick Glance")
        .description("Minimal stats at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickGlanceView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    var body: some View {
        switch family {
        case .systemSmall: QuickGlanceSmall(entry: entry)
        case .systemMedium: QuickGlanceMedium(entry: entry)
        default: QuickGlanceSmall(entry: entry)
        }
    }
}

// ============================================================================
// MARK: - Previews
// ============================================================================

#Preview("Stats S", as: .systemSmall) { DetectionStatsWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Stats M", as: .systemMedium) { DetectionStatsWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Stats L", as: .systemLarge) { DetectionStatsWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Diversity S", as: .systemSmall) { DiversityWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Diversity M", as: .systemMedium) { DiversityWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Diversity L", as: .systemLarge) { DiversityWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Activity S", as: .systemSmall) { ActivityTimelineWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Activity M", as: .systemMedium) { ActivityTimelineWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Trends S", as: .systemSmall) { TrendsWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Trends M", as: .systemMedium) { TrendsWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Trends L", as: .systemLarge) { TrendsWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Community S", as: .systemSmall) { CommunityWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Community M", as: .systemMedium) { CommunityWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Community L", as: .systemLarge) { CommunityWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Glance S", as: .systemSmall) { QuickGlanceWidget() } timeline: { BirdEntry(date: .now, data: .sample) }
#Preview("Glance M", as: .systemMedium) { QuickGlanceWidget() } timeline: { BirdEntry(date: .now, data: .sample) }