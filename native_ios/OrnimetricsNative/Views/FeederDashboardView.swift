import SwiftUI

struct FeederDashboardView: View {
    @EnvironmentObject private var appState: OrnimetricsAppState
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Food Level")
                            .font(.headline)
                        ZStack {
                            Circle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 18)
                            Circle()
                                .trim(from: 0, to: appState.feederProgress)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.6), value: appState.feederProgress)
                            VStack(spacing: 4) {
                                Text("\(Int(appState.feederProgress * 100))%")
                                    .font(.largeTitle.bold())
                                Text("Last synced just now")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 200)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.green.opacity(0.2))
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Actions")
                            .font(.headline)
                        HStack(spacing: 16) {
                            Button {
                                appState.feederProgress = min(1.0, appState.feederProgress + 0.1)
                                HapticsService.softImpact()
                            } label: {
                                Label("Top Off", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                appState.feederProgress = max(0.0, appState.feederProgress - 0.1)
                                HapticsService.softImpact()
                            } label: {
                                Label("Dispense", systemImage: "minus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Live Activity", isOn: $appState.liveActivityEnabled)
                            .onChange(of: appState.liveActivityEnabled) { _ in
                                Task { @MainActor in
                                    await appState.toggleLiveActivity()
                                }
                            }
                        Text("Keep feeder status visible on the Lock Screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding()
            }
            .navigationTitle("Feeder")
            .onAppear { pulse = true }
        }
    }
}
