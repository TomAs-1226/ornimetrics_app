import Charts
import SwiftUI

struct SpeciesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Species Overview", subtitle: "Counts + distribution") {
                    if appState.speciesCounts.isEmpty {
                        Text("No species detections yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        SpeciesPieChart(speciesCounts: appState.speciesCounts)
                    }
                }

                GlassCard(title: "Detected Species", subtitle: "Tap for details") {
                    SpeciesBreakdownList(
                        speciesCounts: appState.speciesCounts,
                        totalDetections: appState.totalDetections,
                        showNavigation: true
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Species")
        .background(
            LinearGradient(colors: [Color.orange.opacity(0.15), Color.yellow.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

struct SpeciesDetailView: View {
    let species: String
    let count: Int
    let total: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(title: species.replacingOccurrences(of: "_", with: " ")) {
                    let percent = total > 0 ? Double(count) / Double(total) : 0
                    Text("\(count) detections")
                        .font(.title2.bold())
                    Text("\(Int(percent * 100))% of total")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(species.replacingOccurrences(of: "_", with: " "))
    }
}
