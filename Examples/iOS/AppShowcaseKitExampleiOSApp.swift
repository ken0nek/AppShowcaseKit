import SwiftUI

/// The iOS example host.
///
/// Only this file is iOS-specific. Everything in `Shared/` compiles anywhere the
/// package does, which is why the platform is a directory rather than a suffix:
/// adding a macOS example is a new target over the same `Shared/`.
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
