import SwiftUI

/// The iOS example host. Its two screens live in `Shared/`.
@main
struct AppShowcaseKitExampleiOSApp: App {
    /// One settings object for both tabs, so a bundle identifier typed into the
    /// inspector is the one the real section resolves on the next tab.
    @State private var settings = InspectorSettings()

    var body: some Scene {
        WindowGroup {
            TabView {
                InspectorScreen(settings: settings)
                    .tabItem { Label("Inspector", systemImage: "slider.horizontal.3") }
                ZeroConfigScreen(settings: settings)
                    .tabItem { Label("Zero-config", systemImage: "list.bullet") }
            }
        }
    }
}
