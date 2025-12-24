import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CommunityView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var caption: String = ""
    @State private var searchQuery: String = ""
    @State private var postLimit: Int = 50
    @State private var tagLowFood = false
    @State private var tagClogged = false
    @State private var tagCleaningDue = false
    @AppStorage("pref_ai_model") private var aiModel = "gpt-4o-mini"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isUnlocked = false
    @State private var lastHiddenAt: Date?

    private let reauthAfter: TimeInterval = 180

    var body: some View {
        BiometricGateView(isUnlocked: $isUnlocked) {
            ScrollView {
                VStack(spacing: 16) {
                    composer

                    searchControls

                    postList
                }
                .padding()
            }
            .navigationTitle("Community")
            .refreshable {
                await appState.loadCommunityFeed()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background, .inactive:
                lastHiddenAt = Date()
            case .active:
                if let lastHiddenAt, Date().timeIntervalSince(lastHiddenAt) > reauthAfter {
                    isUnlocked = false
                }
                self.lastHiddenAt = nil
            @unknown default:
                break
            }
        }
    }

    private var composer: some View {
        GlassCard(title: "New community post", subtitle: "Share a sighting") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Write a caption…", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(selectedImageData == nil ? "Add photo" : "Photo selected", systemImage: "photo")
                }
                .onChange(of: selectedPhoto) { newItem in
                    guard let newItem else { return }
                    Task {
                        selectedImageData = try? await newItem.loadTransferable(type: Data.self)
                    }
                }

                Toggle("Tag low food", isOn: $tagLowFood)
                Toggle("Tag clogged feeder", isOn: $tagClogged)
                Toggle("Tag cleaning due", isOn: $tagCleaningDue)

                Picker("AI model", selection: $aiModel) {
                    Text("GPT-4o Mini").tag("gpt-4o-mini")
                    Text("GPT-4o").tag("gpt-4o")
                    Text("GPT-5.1").tag("gpt-5.1")
                    Text("GPT-5.2").tag("gpt-5.2")
                }
                .pickerStyle(.menu)

                Button("Post") {
                    let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty || selectedImageData != nil else { return }
                    Task {
                        let sensors = CommunitySensorTags(lowFood: tagLowFood, clogged: tagClogged, cleaningDue: tagCleaningDue)
                        if let post = await appState.firebaseService.uploadPost(
                            caption: trimmed,
                            photoData: selectedImageData,
                            weather: appState.environment,
                            sensors: sensors,
                            model: aiModel
                        ) {
                            appState.communityPosts.insert(post, at: 0)
                        }
                        caption = ""
                        selectedImageData = nil
                        selectedPhoto = nil
                        tagLowFood = false
                        tagClogged = false
                        tagCleaningDue = false
                        Haptics.success()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var searchControls: some View {
        GlassCard(title: "Feed controls") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search posts…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)

                Stepper("Post limit: \(postLimit)", value: $postLimit, in: 10...100, step: 10)
            }
        }
    }

    private var postList: some View {
        let filtered = appState.communityPosts.filter { post in
            searchQuery.isEmpty ||
            post.caption.localizedCaseInsensitiveContains(searchQuery) ||
            post.author.localizedCaseInsensitiveContains(searchQuery)
        }
        let limited = Array(filtered.prefix(postLimit))

        return GlassCard(title: "Community feed", subtitle: "\(limited.count) posts") {
            if limited.isEmpty {
                Text("No posts yet. Share the first community update.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(limited) { post in
                        NavigationLink {
                            CommunityPostDetailView(post: post)
                        } label: {
                            CommunityPostRow(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CommunityPostRow: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(post.author)
                    .font(.headline)
                Spacer()
                Text(post.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(post.caption)
                .font(.body)
            if let weather = post.weather {
                Text("\(weather.condition) • \(Int(weather.temperatureC))°C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WrapHStack(items: tagLabels(from: post)) { label in
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
    }

    private func tagLabels(from post: CommunityPost) -> [String] {
        var tags: [String] = [post.timeOfDayTag]
        if post.sensors.lowFood { tags.append("Low food") }
        if post.sensors.clogged { tags.append("Clogged") }
        if post.sensors.cleaningDue { tags.append("Cleaning due") }
        return tags
    }
}

private struct CommunityPostDetailView: View {
    let post: CommunityPost
    @EnvironmentObject private var appState: AppState
    @State private var chatInput: String = ""
    @State private var messages: [AiMessage] = [
        AiMessage(role: "assistant", content: "Ask me about this sighting. I will consider weather, sensors, and time of day when replying.")
    ]
    @State private var sending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CommunityPostCard(post: post)

                Text("AI advice")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(messages) { message in
                        HStack {
                            if message.role == "user" { Spacer() }
                            Text(message.content)
                                .padding(10)
                                .background(message.role == "user" ? Color.mint.opacity(0.2) : Color.white.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            if message.role != "user" { Spacer() }
                        }
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Ask AI about this post", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                Button {
                    send()
                } label: {
                    if sending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(sending)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Post details")
    }

    private func send() {
        let trimmed = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatInput = ""
        messages.append(AiMessage(role: "user", content: trimmed))
        sending = true
        Task {
            let reply = await appState.generateCommunityReply(
                userMessage: trimmed,
                post: post,
                model: appState.config.openAiApiKey.isEmpty ? "gpt-4o-mini" : (UserDefaults.standard.string(forKey: "pref_ai_model") ?? "gpt-4o-mini")
            )
            messages.append(AiMessage(role: "assistant", content: reply))
            sending = false
        }
    }
}

private struct CommunityPostCard: View {
    let post: CommunityPost

    var body: some View {
        GlassCard(title: post.author, subtitle: post.createdAt.formatted(date: .abbreviated, time: .shortened)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(post.caption)
                #if canImport(UIKit)
                if let data = post.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxHeight: 220)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                #endif
                if let url = post.imageURL {
                    AsyncImage(url: url) { phase in
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
                    .frame(maxHeight: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if let weather = post.weather {
                    Text("Weather • \(weather.condition) • \(Int(weather.temperatureC))°C • Humidity \(Int(weather.humidity))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                WrapHStack(items: tagLabels(from: post)) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func tagLabels(from post: CommunityPost) -> [String] {
        var tags: [String] = [post.timeOfDayTag, "Model \(post.model)"]
        if post.sensors.lowFood { tags.append("Low food") }
        if post.sensors.clogged { tags.append("Clogged") }
        if post.sensors.cleaningDue { tags.append("Cleaning due") }
        return tags
    }
}

private struct AiMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}
