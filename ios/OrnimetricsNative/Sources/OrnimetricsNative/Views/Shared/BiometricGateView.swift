import LocalAuthentication
import SwiftUI

struct BiometricGateView<Content: View>: View {
    let content: Content
    @Binding var isUnlocked: Bool
    @State private var errorMessage: String?

    init(isUnlocked: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isUnlocked = isUnlocked
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
                    Text("Use Face ID or your device passcode to protect community posts and biometrics.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button("Unlock") {
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
            if !isUnlocked {
                Task {
                    await authenticate()
                }
            }
        }
    }

    @MainActor
    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = "Device authentication is not available on this device."
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
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
