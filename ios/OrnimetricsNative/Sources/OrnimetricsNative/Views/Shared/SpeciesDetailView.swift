import SwiftUI

struct SpeciesDetailView: View {
    @EnvironmentObject private var appState: AppState
    let speciesKey: String
    @State private var insights: String = ""
    @State private var loadingInsights = true

    private var photos: [DetectionPhoto] {
        appState.detectionPhotos.filter { photo in
            photo.species?.replacingOccurrences(of: "-", with: "_").lowercased() ==
            speciesKey.replacingOccurrences(of: "-", with: "_").lowercased()
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if photos.isEmpty {
                    Text("No recent photos yet.")
                        .foregroundStyle(.secondary)
                } else {
                    TabView {
                        ForEach(photos.prefix(8)) { photo in
                            AsyncImage(url: URL(string: photo.url)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case let .success(image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    Image(systemName: "photo")
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(height: 240)
                            .clipped()
                        }
                    }
                    .frame(height: 240)
                    .tabViewStyle(.page)
                }

                GlassCard(title: "AI insights", subtitle: "Species summary") {
                    if loadingInsights {
                        ProgressView()
                    } else {
                        Text(insights.isEmpty ? "No insights yet." : insights)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(speciesKey.replacingOccurrences(of: "_", with: " "))
        .task {
            await generateInsights()
        }
    }

    private func generateInsights() async {
        loadingInsights = true
        guard !photos.isEmpty else {
            insights = "\(speciesKey.replacingOccurrences(of: "_", with: " ")): no recent photos yet."
            loadingInsights = false
            return
        }

        let sorted = photos.sorted { $0.timestamp < $1.timestamp }
        let first = sorted.first!.timestamp
        let last = sorted.last!.timestamp
        let dayKeys = Set(sorted.map { Calendar.current.startOfDay(for: $0.timestamp) })
        let daysCovered = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0)
        let consistency = Double(dayKeys.count) / Double(daysCovered)
        let consistencyLabel: String
        switch consistency {
        case 0.7...: consistencyLabel = "high"
        case 0.4..<0.7: consistencyLabel = "moderate"
        default: consistencyLabel = "low"
        }
        let count = sorted.count
        let intro = "\(speciesKey.replacingOccurrences(of: "_", with: " ")) appeared \(count) times over \(daysCovered) day(s). Presence consistency is \(consistencyLabel) (\(dayKeys.count) day(s) detected)."
        insights = intro
        loadingInsights = false
    }
}
