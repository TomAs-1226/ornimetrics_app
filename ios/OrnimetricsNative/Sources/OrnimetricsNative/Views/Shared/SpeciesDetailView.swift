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
        let count = photos.count
        if count == 0 {
            insights = "\(speciesKey.replacingOccurrences(of: "_", with: " ")): no recent photos yet."
            loadingInsights = false
            return
        }
        let intro = "\(speciesKey.replacingOccurrences(of: "_", with: " ")) appeared \(count) times recently. Monitor feeder traffic and adjust food levels accordingly."
        insights = intro
        loadingInsights = false
    }
}
