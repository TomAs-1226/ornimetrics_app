import SwiftUI

struct CommunityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var newPost = ""

    var body: some View {
        BiometricGateView {
            ScrollView {
                VStack(spacing: 20) {
                    authCard

                    GlassCard(title: "New Post", subtitle: "Share feeder observations") {
                        TextField("What's happening at your feeder?", text: $newPost, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("Post to Community") {
                            Task {
                                if let post = await appState.firebaseService.uploadPost(body: newPost, photoData: nil) {
                                    appState.communityPosts.insert(post, at: 0)
                                    newPost = ""
                                    Haptics.success()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    ForEach(appState.communityPosts) { post in
                        communityCard(for: post)
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(colors: [Color.orange.opacity(0.2), Color.pink.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
        }
    }

    private var authCard: some View {
        GlassCard(title: "Community Center", subtitle: appState.isAuthenticated ? "Signed in" : "Sign in to post") {
            if appState.isAuthenticated {
                Text("Welcome back! You're ready to join the discussion.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    Button("Sign In") {
                        Task {
                            await appState.authenticateUser(email: email, password: password)
                            Haptics.impact(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func communityCard(for post: CommunityPost) -> some View {
        GlassCard(title: post.author, subtitle: post.createdAt.formatted(date: .abbreviated, time: .shortened)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(post.body)
                HStack(spacing: 12) {
                    Label(post.weather, systemImage: "cloud.sun")
                    Label("\(post.humidity)%", systemImage: "drop.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !post.sensorTags.isEmpty {
                    WrapHStack(items: post.sensorTags) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                    }
                }

                Button("Ask AI about this post") {
                    Task {
                        await appState.generatePostInsights(for: post)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
