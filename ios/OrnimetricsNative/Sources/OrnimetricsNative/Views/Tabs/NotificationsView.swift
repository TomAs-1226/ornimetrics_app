import SwiftUI

struct NotificationsView: View {
    @State private var feederAlerts = true
    @State private var lowFoodThreshold: Double = 0.25
    @State private var humidityAlerts = true
    @State private var quietHours = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Feeder Alerts", subtitle: "Food level + maintenance") {
                    Toggle("Enable feeder notifications", isOn: $feederAlerts)
                    VStack(alignment: .leading) {
                        Text("Low food threshold")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $lowFoodThreshold, in: 0.1...0.9, step: 0.05)
                        Text("Alert when below \(Int(lowFoodThreshold * 100))%")
                            .font(.subheadline)
                    }
                }

                GlassCard(title: "Environment triggers", subtitle: "Weather + humidity") {
                    Toggle("Humidity warnings", isOn: $humidityAlerts)
                    Toggle("Quiet hours", isOn: $quietHours)
                    Text("Notifications pause between 10pm and 6am to preserve local wildlife.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                GlassCard(title: "Haptics + animations", subtitle: "System feedback") {
                    Text("Haptic pulses confirm new sensor data or successful community posts.")
                        .foregroundStyle(.secondary)
                    Button("Test haptic") {
                        Haptics.impact(.heavy)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .background(
            LinearGradient(colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
