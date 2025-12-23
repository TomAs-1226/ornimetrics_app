import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var animatePulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                GlassCard(title: "Feeder Status", subtitle: "Live telemetry") {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: appState.feederStatus.foodLevel) {
                            Text("Food level")
                        } currentValueLabel: {
                            Text("\(Int(appState.feederStatus.foodLevel * 100))%")
                        }
                        .tint(.green)

                        HStack {
                            InfoPill(title: "Last refill", value: appState.feederStatus.lastRefill.formatted(date: .abbreviated, time: .shortened))
                            InfoPill(title: "Capacity", value: "\(Int(appState.feederStatus.hopperCapacity))%")
                        }
                    }
                }

                GlassCard(title: "Maintenance", subtitle: "Next action") {
                    HStack {
                        Image(systemName: "wrench.adjustable")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(appState.feederStatus.nextMaintenance.formatted(date: .abbreviated, time: .omitted))
                                .font(.title3.bold())
                            Text("Scheduled cleanup and sensor check")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            Haptics.success()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                GlassCard(title: "Weather snapshot", subtitle: "From your location") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(appState.environment.condition)
                                .font(.title2.bold())
                            Text("\(Int(appState.environment.temperatureC))°C • \(appState.environment.humidity)% humidity")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "cloud.sun.fill")
                            .font(.largeTitle)
                    }
                }

                GlassCard(title: "AI Insights", subtitle: "On-device summary") {
                    Text(appState.aiSummary.isEmpty ? "Ask AI about a community post to see insights here." : appState.aiSummary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color.mint.opacity(0.2), Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animatePulse.toggle()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome back")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Ornimetrics")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Circle()
                .fill(animatePulse ? Color.mint.opacity(0.4) : Color.mint.opacity(0.2))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(.white)
                )
        }
    }
}

struct InfoPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
