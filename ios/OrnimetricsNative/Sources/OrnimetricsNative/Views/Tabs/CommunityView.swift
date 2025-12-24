import SwiftUI

struct CommunityView: View {
    @State private var postText: String = ""
    @State private var posts: [Post] = Post.sample

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Write a post…", text: $postText)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Post") {
                        let trimmed = postText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        posts.insert(Post(author: "You", body: trimmed, date: Date()), at: 0)
                        postText = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                List(posts) { post in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(post.author)
                                .font(.headline)
                            Spacer()
                            Text(post.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(post.body)
                            .font(.body)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("Community")
        }
    }
}

// MARK: - Local model (keeps this file compiling)
private struct Post: Identifiable, Hashable {
    let id = UUID()
    let author: String
    let body: String
    let date: Date

    static let sample: [Post] = [
        Post(author: "Ornimetrics", body: "Welcome to Community.", date: Date().addingTimeInterval(-3600)),
        Post(author: "Birder", body: "Saw a finch today near the feeder!", date: Date().addingTimeInterval(-7200)),
    ]
}

