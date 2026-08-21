import AppShowcaseUI
import SwiftUI

/// The real shipping component, unmodified, in the shape an adopter would use
/// it: a `Form` with the section placed unconditionally at the bottom.
///
/// Tap style comes from the Inspector, because a picker that changes nothing on
/// the screen people actually judge is worse than no picker. It is a parameter
/// an adopter writes too — a literal, once — so the shape survives it. Zero
/// configuration here means the section finds its own roster with nothing wired
/// to it, not that it takes no arguments.
///
/// The `.environment` line is the only thing here that a real adopter would not
/// write. Without it this renders nothing at all — correctly. This app is not on
/// the App Store, so its own bundle identifier resolves to no artist, the chain
/// ends at `hostAppNotFound`, and the section collapses to nothing visible — no
/// header, no rows, no stray separator. That behavior is exactly why
/// `ShowcaseHostOverride` exists, and comparing the two tabs is the fastest way
/// to see it.
struct ZeroConfigScreen: View {
    let settings: InspectorSettings

    /// The host's own settings are scenery — they exist so the showcase section
    /// is seen sitting under something. Inert scenery reads as a broken screen
    /// though, so these two do what their kind of row does: one toggles, one
    /// pushes.
    @State private var soundEffects = true
    @State private var notifications = false

    var body: some View {
        NavigationStack {
            Form {
                Section("A host app's own settings") {
                    Toggle("Sound effects", isOn: $soundEffects)
                    NavigationLink("Notifications") {
                        Form {
                            Toggle("Allow notifications", isOn: $notifications)
                        }
                        .navigationTitle("Notifications")
                    }
                }

                AppShowcaseSection(tapStyle: settings.tapStyle) {
                    Text("More from me")
                }
            }
            .navigationTitle("Zero-config")
        }
        .environment(
            \.showcaseHostOverride,
            .init(bundleID: settings.bundleID, storefront: settings.storefront)
        )
    }
}
