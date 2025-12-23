import Foundation
import LocalAuthentication

struct FaceIDService {
    func authenticate() async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error ?? NSError(domain: "FaceID", code: -1, userInfo: [NSLocalizedDescriptionKey: "Face ID unavailable"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Community Center") { success, evalError in
                if let evalError {
                    continuation.resume(throwing: evalError)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
