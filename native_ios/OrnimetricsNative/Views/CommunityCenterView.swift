import SwiftUI

struct CommunityCenterView: View {
    @EnvironmentObject private var appState: OrnimetricsAppState
    @State private var post = CommunityPost.sample
    @State private var aiInsight: String = ""
    @State private var isLoadingInsight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    faceIDCard
                    if appState.isFaceIDUnlocked {
                        postCard
                        aiCard
                    } else {
                        Text("Unlock with Face ID to access Community Center.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Community Center")
        }
    }

    private var faceIDCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community Access")
                .font(.headline)
            HStack {
                Text(appState.isFaceIDUnlocked ? "Unlocked" : "Locked")
                    .foregroundStyle(appState.isFaceIDUnlocked ? .green : .secondary)
                Spacer()
                Button {
                    Task { @MainActor in
                        await appState.toggleFaceID()
                    }
                } label: {
                    Label("Face ID", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(post.title)
                .font(.headline)
            Text(post.body)
            Text(post.weatherTag)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ecology Insights")
                .font(.headline)
            if isLoadingInsight {
                ProgressView("Analyzing with Apple Intelligence...")
            } else {
                Text(aiInsight.isEmpty ? "Tap below to generate on-device insight." : aiInsight)
                    .foregroundStyle(aiInsight.isEmpty ? .secondary : .primary)
            }
            Button {
                Task {
                    await generateInsight()
                }
            } label: {
                Label("Ask Apple Intelligence", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func generateInsight() async {
        isLoadingInsight = true
        defer { isLoadingInsight = false }
        do {
            let service = AIInsightService()
            aiInsight = try await service.generateInsight(from: post.body)
        } catch {
            aiInsight = "Unable to generate insights at the moment."
        }
    }
}
