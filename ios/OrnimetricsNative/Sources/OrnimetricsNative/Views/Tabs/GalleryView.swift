import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshing = false
    @State private var selectedIndex: Int = 0
    @State private var showCarousel = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Detection Gallery", subtitle: "Recent snapshots") {
                    if appState.detectionPhotos.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.largeTitle)
                            Text("No snapshots yet.")
                                .font(.headline)
                            Text("When your device uploads images to the photo_snapshots feed, they will appear here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let checked = appState.lastUpdated {
                                Text("Checked: \(checked.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)]) {
                            ForEach(Array(appState.detectionPhotos.enumerated()), id: \.element.id) { index, photo in
                                Button {
                                    selectedIndex = index
                                    showCarousel = true
                                } label: {
                                    DetectionPhotoCell(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Recent")
        .background(
            LinearGradient(colors: [Color.gray.opacity(0.15), Color.mint.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .refreshable {
            await refresh()
        }
        .fullScreenCover(isPresented: $showCarousel) {
            PhotoCarouselView(photos: appState.detectionPhotos, initialIndex: selectedIndex)
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await appState.loadDetections()
        Haptics.impact(.light)
    }
}

struct PhotoCarouselView: View {
    let photos: [DetectionPhoto]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(photos: [DetectionPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        self._selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    VStack(spacing: 16) {
                        AsyncImage(url: URL(string: photo.url)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .tint(.white)
                            case let .success(image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(.white)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxHeight: 360)

                        Text(photo.species?.replacingOccurrences(of: "_", with: " ") ?? "Unknown species")
                            .foregroundStyle(.white)
                            .font(.headline)
                        Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.caption)
                    }
                    .padding()
                    .tag(index)
                }
            }
            .tabViewStyle(.page)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: DetectionPhoto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: URL(string: photo.url)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.2))
                            ProgressView()
                        }
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.2))
                            Image(systemName: "photo")
                        }
                    @unknown default:
                        Color.gray
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(photo.species?.replacingOccurrences(of: "_", with: " ") ?? "Unknown species")
                        .font(.title3.bold())
                    Text(photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                if let weather = photo.weatherAtCapture {
                    GlassCard(title: "Weather at capture") {
                        Text("\(weather.condition) • \(Int(weather.temperatureC))°C")
                        Text("Humidity \(Int(weather.humidity))% • Wind \(Int(weather.windKph ?? 0)) kph")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Snapshot")
    }
}
