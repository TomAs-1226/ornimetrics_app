import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var animatePulse = false
    @State private var selection: DetectionSection = .recent

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                detectionSummary

                liveDetections

                distributionCard

                detectedSpecies

                GlassCard(title: "Maintenance", subtitle: "Next action") {
                    HStack {
                        Image(systemName: "wrench.adjustable")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(appState.feederStatus.nextMaintenance.formatted(date: .abbreviated, time: .omitted))
                                .font(.title3.bold())
                            Text("Scheduled cleanup and sensor check")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            Haptics.success()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                GlassCard(title: "Weather snapshot", subtitle: "From your location") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.environment.condition)
                            .font(.title2.bold())
                        Text("\(Int(appState.environment.temperatureC))°C • \(Int(appState.environment.humidity))% humidity")
                            .foregroundStyle(.secondary)
                        Text("Feels like \(Int(appState.environment.feelsLikeC ?? appState.environment.temperatureC))°C • UV \(Int(appState.environment.uvIndex ?? 0))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard(title: "AI Insights", subtitle: "On-device summary") {
                    Text(appState.aiSummary.isEmpty ? "Ask AI about a community post to see insights here." : appState.aiSummary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color.mint.opacity(0.2), Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animatePulse.toggle()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome back")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Ornimetrics")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Circle()
                .fill(animatePulse ? Color.mint.opacity(0.4) : Color.mint.opacity(0.2))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(.white)
                )
        }
    }

    private var detectionSummary: some View {
        HStack(spacing: 16) {
            StatCard(title: "Total Detections", value: "\(appState.totalDetections)", systemImage: "track_changes")
            StatCard(title: "Unique Species", value: "\(appState.speciesCounts.keys.count)", systemImage: "pawprint")
        }
    }

    private var liveDetections: some View {
        GlassCard(title: "Live Animal Detection", subtitle: "Recent and species views") {
            Picker("Detection view", selection: $selection) {
                ForEach(DetectionSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            if selection == .recent {
                DetectionPhotoGrid(photos: appState.detectionPhotos)
            } else {
                SpeciesBreakdownList(speciesCounts: appState.speciesCounts, totalDetections: appState.totalDetections)
            }
        }
    }

    private var distributionCard: some View {
        GlassCard(title: "Species Distribution", subtitle: "Pie chart") {
            if appState.speciesCounts.isEmpty {
                Text("No species data to display.")
                    .foregroundStyle(.secondary)
            } else {
                SpeciesPieChart(speciesCounts: appState.speciesCounts)
            }
        }
    }

    private var detectedSpecies: some View {
        GlassCard(title: "Detected Species", subtitle: "Recent counts") {
            SpeciesBreakdownList(speciesCounts: appState.speciesCounts, totalDetections: appState.totalDetections)
        }
    }
}

private enum DetectionSection: String, CaseIterable, Identifiable {
    case recent
    case species

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .species: return "Species"
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        GlassCard(title: value, subtitle: title) {
            HStack {
                Spacer()
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.mint)
            }
        }
    }
}

private struct DetectionPhotoGrid: View {
    let photos: [DetectionPhoto]

    var body: some View {
        if photos.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                Text("No recent detections yet.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)]) {
                ForEach(photos) { photo in
                    DetectionPhotoCell(photo: photo)
                }
            }
        }
    }
}

private struct DetectionPhotoCell: View {
    let photo: DetectionPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: photo.url)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.2))
                        ProgressView()
                    }
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.2))
                        Image(systemName: "photo")
                    }
                @unknown default:
                    Color.gray
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(photo.species?.replacingOccurrences(of: "_", with: " ") ?? "Unknown species")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpeciesBreakdownList: View {
    let speciesCounts: [String: Int]
    let totalDetections: Int

    var body: some View {
        let sorted = speciesCounts.sorted { $0.value > $1.value }
        if sorted.isEmpty {
            Text("No species data available.")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 12) {
                ForEach(sorted, id: \.key) { species, count in
                    let percent = totalDetections > 0 ? (Double(count) / Double(totalDetections)) : 0
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(species.replacingOccurrences(of: "_", with: " "))
                                .font(.subheadline.bold())
                            Text("\(count) detections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(percent * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: percent)
                        .tint(.mint)
                }
            }
        }
    }
}

private struct SpeciesPieChart: View {
    let speciesCounts: [String: Int]

    var body: some View {
        let data = groupedCounts(speciesCounts)
        Chart(data) { item in
            SectorMark(
                angle: .value("Detections", item.count),
                innerRadius: .ratio(0.6),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Species", item.name))
        }
        .chartLegend(position: .bottom)
        .frame(height: 260)
    }

    private func groupedCounts(_ counts: [String: Int]) -> [SpeciesSlice] {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        let sorted = counts.sorted { $0.value > $1.value }
        var slices: [SpeciesSlice] = []
        var otherTotal = 0
        for (name, count) in sorted {
            let pct = (Double(count) / Double(total)) * 100
            if pct < 5 {
                otherTotal += count
            } else {
                slices.append(SpeciesSlice(name: name.replacingOccurrences(of: "_", with: " "), count: count))
            }
        }
        if otherTotal > 0 {
            slices.append(SpeciesSlice(name: "Other", count: otherTotal))
        }
        return slices
    }
}

private struct SpeciesSlice: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct InfoPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
