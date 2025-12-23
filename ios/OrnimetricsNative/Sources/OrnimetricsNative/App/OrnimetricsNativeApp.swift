import SwiftUI

@available(iOS 18.0, *)
@main
struct OrnimetricsNativeApp: App {
    @StateObject private var appState = AppState(config: AppConfig.load())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await appState.bootstrap()
                }
        }
    }
}
