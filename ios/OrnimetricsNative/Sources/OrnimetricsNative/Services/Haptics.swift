import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

enum Haptics {

    @MainActor
    static func success() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        // No-op
        #endif
    }

    @MainActor
    static func warning() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        // No-op
        #endif
    }

    @MainActor
    static func impact(_ style: ImpactStyle = .medium) {
        guard isEnabled else { return }
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style.uiKitStyle)
        generator.prepare()
        generator.impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        // No-op
        #endif
    }
}

// MARK: - Cross-platform impact style (so this file compiles everywhere)
extension Haptics {
    enum ImpactStyle: Sendable {
        case light, medium, heavy, soft, rigid
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "pref_haptics_enabled") as? Bool ?? true
    }
}

#if canImport(UIKit)
private extension Haptics.ImpactStyle {
    var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        case .soft: return .soft
        case .rigid: return .rigid
        }
    }
}
#endif
