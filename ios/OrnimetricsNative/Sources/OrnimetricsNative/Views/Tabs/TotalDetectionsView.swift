import SwiftUI

struct TotalDetectionsView: View {
    let total: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard(title: "Total Detections", subtitle: "All time") {
                    Text("\(total)")
                        .font(.system(size: 56, weight: .bold))
                    Text("All detections logged by your Ornimetrics device.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Total Detections")
    }
}
