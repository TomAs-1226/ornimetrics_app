import LocalAuthentication
import SwiftUI

struct BiometricGateView<Content: View>: View {
    let content: Content
    @State private var isUnlocked = false
    @State private var errorMessage: String?

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if isUnlocked {
                content
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "faceid")
                        .font(.system(size: 42))
                    Text("Unlock Community Center")
                        .font(.title2.bold())
                    Text("Use Face ID to protect community posts and biometrics.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button("Use Face ID") {
                        Task {
                            await authenticate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onAppear {
            Task {
                await authenticate()
            }
        }
    }

    @MainActor
    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            errorMessage = "Face ID is not available on this device."
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                          localizedReason: "Access the community center")
            if success {
                isUnlocked = true
                Haptics.success()
            }
        } catch {
            errorMessage = "Face ID failed. Try again."
            Haptics.warning()
        }
    }
}
