import Charts
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var notifications: NotificationsCenter
    @State private var animatePulse = false
    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @State private var showAllTrends = false
    @State private var showHourlyDetail = false

    init(notifications: NotificationsCenter) {
        self.notifications = notifications
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                heroDistribution

                shortenedSpeciesList

                maintenanceBanner

                notificationCard

                detectionSummary

                biodiversityCard

                hourlyActivityCard

                tasksCard

                trendsCard

                aiAnalysisCard
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
        .sheet(isPresented: $showAllTrends) {
            TrendsSheet(trends: appState.trendSignals)
        }
        .sheet(isPresented: $showAddTask) {
            NewTaskSheet(
                title: $newTaskTitle,
                onSave: {
                    let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    appState.addTask(EcoTask(title: title, category: "user", priority: 2, source: "user"))
                    newTaskTitle = ""
                    showAddTask = false
                },
                onCancel: {
                    newTaskTitle = ""
                    showAddTask = false
                }
            )
        }
        .sheet(isPresented: $showHourlyDetail) {
            HourlyActivityDetailSheet(photos: appState.detectionPhotos)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Animal Detection")
                        .font(.title2.bold())
                    Text("Real-time data from Ornimetrics")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(animatePulse ? Color.mint.opacity(0.4) : Color.mint.opacity(0.2))
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "leaf.fill").foregroundStyle(.white))
            }
            if let updated = appState.lastUpdated {
                Text("Last updated: \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroDistribution: some View {
        GlassCard(title: "Species Distribution", subtitle: "Pie chart overview") {
            if appState.speciesCounts.isEmpty {
                Text("No species data to display.")
                    .foregroundStyle(.secondary)
            } else {
                SpeciesPieChart(speciesCounts: appState.speciesCounts)
                    .frame(height: 300)
            }
        }
    }

    private var shortenedSpeciesList: some View {
        GlassCard(title: "Detected Species", subtitle: "Top sightings") {
            SpeciesBreakdownList(
                speciesCounts: appState.speciesCounts,
                totalDetections: appState.totalDetections,
                showNavigation: true,
                limit: 4
            )
        }
    }

    private var maintenanceBanner: some View {
        let prefs = notifications.preferences
        let last = prefs.lastCleaned
        let daysSince = last.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0 } ?? 9999
        let showBanner = daysSince >= 7

        return Group {
            if showBanner {
                GlassCard(title: "Maintenance", subtitle: "Feeder cleaning reminder") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(daysSince > 9000 ? "No cleaning date recorded yet" : "It's been \(daysSince) day(s) since cleaning")
                                .font(.headline)
                            Text("Regularly cleaning feeders helps reduce disease risk for birds.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Mark cleaned") {
                            notifications.markCleaned()
                            Haptics.success()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var notificationCard: some View {
        Group {
            if !notifications.permissionsPrompted {
                GlassCard(title: "Feeder notifications", subtitle: "Configure alerts") {
                    Text("Configure low food, clog, and cleaning reminders. Alerts will flow from your production device telemetry.")
                        .foregroundStyle(.secondary)
                    Button("Enable notifications") {
                        notifications.requestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var detectionSummary: some View {
        HStack(spacing: 16) {
            NavigationLink {
                TotalDetectionsView(total: appState.totalDetections, speciesCounts: appState.speciesCounts)
            } label: {
                StatCard(
                    title: "Total Detections",
                    value: "\(appState.totalDetections)",
                    systemImage: "magnifyingglass",
                    copyText: "Total detections: \(appState.totalDetections)"
                )
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)

            NavigationLink {
                SpeciesView()
            } label: {
                let speciesList = appState.speciesCounts.keys.sorted().joined(separator: ", ")
                StatCard(
                    title: "Unique Species",
                    value: "\(appState.speciesCounts.keys.count)",
                    systemImage: "pawprint",
                    copyText: "Unique species: \(speciesList)"
                )
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var biodiversityCard: some View {
        let counts = appState.speciesCounts
        let total = counts.values.reduce(0, +)
        if total == 0 {
            GlassCard(title: "Species Diversity Metrics") {
                Text("No data for diversity metrics.")
                    .foregroundStyle(.secondary)
            }
        } else {
            let probs = counts.values.map { Double($0) / Double(total) }
            var shannon = 0.0
            var sumP2 = 0.0
            for p in probs where p > 0 {
                shannon += -p * log(p)
                sumP2 += p * p
            }
            let simpson = 1 - sumP2
            let s = counts.count
            let hMax = s > 0 ? log(Double(s)) : 0
            let evenness = (s > 1 && hMax > 0) ? (shannon / hMax) : 0

            let metrics: [BiodiversityMetric] = [
                BiodiversityMetric(title: "Shannon Diversity Index (H')", value: shannon),
                BiodiversityMetric(title: "Gini–Simpson Index (1−D)", value: simpson),
                BiodiversityMetric(title: "Pielou Evenness (J')", value: evenness)
            ]
            GlassCard(title: "Species Diversity Metrics", subtitle: "Hold to copy") {
                WrapHStack(items: metrics) { item in
                    let value = item.value.isFinite ? String(format: "%.2f", item.value) : "—"
                    InfoPill(title: item.title, value: value)
                }
            }
            .contextMenu {
                Button("Copy metrics") {
                    let text = "H': \(String(format: "%.2f", shannon)), 1−D: \(String(format: "%.2f", simpson)), J': \(String(format: "%.2f", evenness))"
                    #if canImport(UIKit)
                    UIPasteboard.general.string = text
                    #endif
                }
            }
        }
    }

    private var hourlyActivityCard: some View {
        GlassCard(title: "Hourly Activity", subtitle: "Time of day distribution") {
            HourlyActivityChart(photos: appState.detectionPhotos)
            Button("View hourly details") {
                showHourlyDetail = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var tasksCard: some View {
        let pending = appState.tasks.filter { !$0.done }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return ($0.dueAt ?? Date.distantFuture) < ($1.dueAt ?? Date.distantFuture)
        }
        let top = pending.prefix(3)

        return GlassCard(title: "Action Tasks") {
            HStack {
                Spacer()
                Button {
                    showAddTask = true
                } label: {
                    Label("Add task", systemImage: "plus.circle.fill")
                }
            }
            if top.isEmpty {
                Text("No pending tasks yet. Run an Ecological AI Analysis or add one.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(top) { task in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                appState.toggleTask(task, done: true)
                            } label: {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.subheadline.bold())
                                if let desc = task.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Text(task.category.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.thinMaterial)
                                        .clipShape(Capsule())
                                    if let due = task.dueAt {
                                        Text("Due: \(due.formatted(.dateTime.month().day()))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var trendsCard: some View {
        let trends = appState.trendSignals.prefix(4)
        return GlassCard(title: "Recent Trends", subtitle: "Last 7 days vs prior") {
            if appState.trendRollup.hasAnyData {
                HStack {
                    Text("\(appState.trendRollup.recentTotal) detections in last 7d")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appState.trendRollup.pctLabel)
                        .font(.caption.bold())
                        .foregroundStyle(appState.trendRollup.direction == "rising" ? .green : appState.trendRollup.direction == "falling" ? .red : .secondary)
                }
            }
            if trends.isEmpty {
                Text("No recent changes to report.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(trends) { trend in
                        TrendRow(trend: trend)
                    }
                }
            }
            Button("View all changes") {
                showAllTrends = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aiAnalysisCard: some View {
        GlassCard(title: "Ecological AI Analysis", subtitle: "On-device summary") {
            Text(appState.aiAnalysis.isEmpty ? "Run the analysis to see guidance on feeder care and habitat safety." : appState.aiAnalysis)
                .foregroundStyle(.secondary)
            Button("Run analysis") {
                Task { await appState.generateAiAnalysis() }
            }
            .buttonStyle(.borderedProminent)
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
    var copyText: String?

    var body: some View {
        GlassCard(title: value, subtitle: title) {
            HStack {
                Spacer()
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.mint)
            }
        }
        .frame(minHeight: 130)
        .contextMenu {
            if let copyText {
                Button("Copy") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = copyText
                    #endif
                }
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

struct DetectionPhotoCell: View {
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

struct SpeciesBreakdownList: View {
    let speciesCounts: [String: Int]
    let totalDetections: Int
    var showNavigation: Bool = false
    var limit: Int? = nil

    var body: some View {
        let sorted = speciesCounts.sorted { $0.value > $1.value }
        let list = limit.map { Array(sorted.prefix($0)) } ?? sorted
        if list.isEmpty {
            Text("No species data available.")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 12) {
                ForEach(list, id: \.key) { species, count in
                    let percent = totalDetections > 0 ? (Double(count) / Double(totalDetections)) : 0
                    Group {
                        if showNavigation {
                            NavigationLink {
                                SpeciesDetailView(speciesKey: species)
                            } label: {
                                speciesRow(species: species, count: count, percent: percent)
                            }
                            .buttonStyle(.plain)
                        } else {
                            speciesRow(species: species, count: count, percent: percent)
                        }
                    }
                }
            }
        }
    }

    private func speciesRow(species: String, count: Int, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

struct SpeciesPieChart: View {
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

private struct HourlyActivityChart: View {
    let photos: [DetectionPhoto]

    var body: some View {
        let counts = hourlyCounts(from: photos)
        let entries = counts.enumerated().map { index, value in
            HourlyEntry(hour: index, count: value)
        }
        if entries.allSatisfy({ $0.count == 0 }) {
            Text("No hourly activity yet.")
                .foregroundStyle(.secondary)
        } else {
            Chart(entries) { entry in
                BarMark(
                    x: .value("Hour", entry.hour),
                    y: .value("Detections", entry.count)
                )
                .foregroundStyle(Color.mint.gradient)
            }
            .chartXAxis {
                AxisMarks(values: stride(from: 0, through: 23, by: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)h")
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    private func hourlyCounts(from photos: [DetectionPhoto]) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        let calendar = Calendar.current
        for photo in photos {
            let hour = calendar.component(.hour, from: photo.timestamp)
            if hour >= 0 && hour < 24 {
                counts[hour] += 1
            }
        }
        return counts
    }
}

private struct HourlyEntry: Identifiable {
    let id = UUID()
    let hour: Int
    let count: Int
}

private struct TrendRow: View {
    let trend: TrendSignal

    var body: some View {
        HStack {
            Image(systemName: trend.direction == "rising" ? "arrow.up.right" : trend.direction == "falling" ? "arrow.down.right" : "minus")
                .foregroundStyle(trend.direction == "rising" ? Color.green : trend.direction == "falling" ? Color.red : Color.secondary)
            VStack(alignment: .leading) {
                Text(trend.species.replacingOccurrences(of: "_", with: " "))
                    .font(.subheadline.bold())
                Text("Δ \(trend.delta >= 0 ? "+" : "")\(trend.delta) (\(Int(trend.changeRate * 100))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(trend.start) → \(trend.end)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BiodiversityMetric: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let value: Double
}

private struct HourlyActivityDetailSheet: View {
    let photos: [DetectionPhoto]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(hourlyRows) { row in
                HStack {
                    Text("\(row.hour)h")
                        .frame(width: 40, alignment: .leading)
                    ProgressView(value: Double(row.count), total: Double(maxCount))
                        .tint(.mint)
                    Text("\(row.count)")
                        .frame(width: 40, alignment: .trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hourly Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var hourlyRows: [HourlyEntry] {
        var counts = Array(repeating: 0, count: 24)
        let calendar = Calendar.current
        for photo in photos {
            let hour = calendar.component(.hour, from: photo.timestamp)
            if hour >= 0 && hour < 24 {
                counts[hour] += 1
            }
        }
        return counts.enumerated().map { HourlyEntry(hour: $0.offset, count: $0.element) }
    }

    private var maxCount: Int {
        hourlyRows.map(\.count).max() ?? 1
    }
}

private struct NewTaskSheet: View {
    @Binding var title: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create a new task")
                    .font(.title2.bold())
                TextField("Describe the action", text: $title, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 120)
                Spacer()
            }
            .padding()
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { onSave() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct TrendsSheet: View {
    let trends: [TrendSignal]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(trends) { trend in
                TrendRow(trend: trend)
            }
            .navigationTitle("All recent changes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
