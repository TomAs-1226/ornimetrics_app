import Charts
import SwiftUI

struct SpeciesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSpecies: IdentifiedSpecies?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                coverSection
                overviewSection
                speciesList
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Unique Species")
        .background(
            LinearGradient(colors: [Color.orange.opacity(0.15), Color.yellow.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .sheet(item: $selectedSpecies) { species in
            NavigationStack {
                SpeciesDetailView(speciesKey: species.name)
                    .environmentObject(appState)
            }
        }
    }

    private var coverSection: some View {
        let sorted = appState.speciesCounts.sorted { $0.value > $1.value }
        let coverPhoto = coverPhotoForSpecies(sorted.first?.key)
        let total = appState.speciesCounts.values.reduce(0, +)

        return VStack(spacing: 0) {
            if let coverPhoto {
                AsyncImage(url: URL(string: coverPhoto.url)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Rectangle().fill(Color.gray.opacity(0.2))
                            ProgressView()
                        }
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        ZStack {
                            Rectangle().fill(Color.gray.opacity(0.2))
                            Image(systemName: "photo")
                        }
                    @unknown default:
                        Color.gray
                    }
                }
                .frame(height: 200)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(Image(systemName: "photo").font(.largeTitle))
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("\(appState.speciesCounts.count) unique species")
                        .font(.headline)
                    Text("Total detections: \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }

    private var overviewSection: some View {
        GlassCard(title: "Species Overview", subtitle: "Counts + distribution") {
            if appState.speciesCounts.isEmpty {
                Text("No species detections yet.")
                    .foregroundStyle(.secondary)
            } else {
                SpeciesPieChart(speciesCounts: appState.speciesCounts)
            }
        }
        .padding(.horizontal)
    }

    private var speciesList: some View {
        let entries = appState.speciesCounts.sorted { $0.value > $1.value }
        let total = max(1, appState.totalDetections)

        return VStack(spacing: 12) {
            ForEach(entries, id: \.key) { species, count in
                let percent = Double(count) / Double(total)
                Button {
                    selectedSpecies = IdentifiedSpecies(name: species)
                } label: {
                    SpeciesRowCard(
                        species: species,
                        count: count,
                        percent: percent,
                        photo: coverPhotoForSpecies(species)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func coverPhotoForSpecies(_ species: String?) -> DetectionPhoto? {
        guard let species else { return nil }
        return appState.detectionPhotos.first { photo in
            photo.species?.replacingOccurrences(of: "-", with: "_").lowercased() ==
            species.replacingOccurrences(of: "-", with: "_").lowercased()
        }
    }
}

private struct IdentifiedSpecies: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

private struct SpeciesRowCard: View {
    let species: String
    let count: Int
    let percent: Double
    let photo: DetectionPhoto?

    var body: some View {
        GlassCard(title: species.replacingOccurrences(of: "_", with: " "), subtitle: "\(count) detections") {
            HStack(spacing: 12) {
                if let photo {
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
                    .frame(width: 90, height: 70)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected \(count) times (\(Int(percent * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: percent)
                        .tint(.mint)
                }
            }
        }
    }
}
