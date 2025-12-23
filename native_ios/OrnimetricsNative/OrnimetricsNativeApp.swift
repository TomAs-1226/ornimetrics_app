import SwiftUI

@main
struct OrnimetricsNativeApp: App {
    @StateObject private var appState = OrnimetricsAppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .onAppear {
                    appState.bootstrap()
                }
        }
    }
}
