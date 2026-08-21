import AppShowcaseCore
import AppShowcaseUI
import SwiftUI

/// Drives `ShowcaseLoader.load()` directly, and that choice is the screen's
/// reason to exist.
///
/// `ShowcaseLoader.resolved(overlay:override:)` — what the shipping section
/// calls — swallows every error by contract, because a Settings screen must
/// never tell a user that a cross-promotion failed. That is right for the
/// product and useless for a harness, so this screen takes the throwing path and
/// names what came back: `hostAppNotFound`, `rosterMissingEntityParameter`,
/// `malformedResponse`, `transportFailed`.
struct InspectorScreen: View {
    @Bindable var settings: InspectorSettings

    @State private var apps: [ShowcaseApp] = []
    @State private var failure: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                hostSection
                behaviorSection

                if let failure {
                    Section("Error") {
                        Text(failure)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.red)
                    }
                }

                rosterSection
            }
            .navigationTitle("Inspector")
            .overlay {
                if loading { ProgressView() }
            }
            .task { await load() }
        }
    }

    private var hostSection: some View {
        Section {
            TextField("Bundle identifier", text: $settings.bundleID)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Picker("Storefront", selection: $settings.alpha3) {
                ForEach(InspectorSettings.storefronts, id: \.self) { Text($0) }
            }
        } header: {
            Text("Host")
        } footer: {
            Text("Any App Store app's identifier. The roster is its developer's.")
        }
    }

    private var behaviorSection: some View {
        Section {
            Picker("Tap style", selection: $settings.tapStyle) {
                ForEach(ShowcaseTapStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            Toggle("Use cache", isOn: $settings.cacheEnabled)
            Button("Load") {
                Task { await load() }
            }
        } header: {
            Text("Behavior")
        } footer: {
            // Both lines are read on a device, by someone wondering why the app
            // is not doing what they just told it to.
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Tap style drives the rows below and the Zero-config tab, so a style "
                        + "can be judged on the screen it would ship on."
                )
                Text(
                    "With storeSheet, tap a row and then Cancel — the sheet should close. "
                        + "That check needs a real App Store, so no simulator can make it."
                )
            }
        }
    }

    private var rosterSection: some View {
        Section("Roster (\(apps.count))") {
            if apps.isEmpty && failure == nil && !loading {
                Text("Nothing to show.").foregroundStyle(.secondary)
            }
            ForEach(apps) { app in
                Button {
                    settings.tapStyle.makePresenter().present(app, attribution: .none)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                        Text("\(app.platform == .iOS ? "iOS" : "macOS") · \(app.genre)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    // The reload is the point: `excluded` only reaches the
                    // roster through `settings.overlay`, which only `load()`
                    // reads, so a swipe that does not reload looks broken to
                    // the person holding the device.
                    Button("Exclude") {
                        settings.excluded.insert(app.id)
                        Task { await load() }
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        failure = nil
        do {
            apps = try await ShowcaseLoader(
                hostBundleID: settings.bundleID,
                storefront: settings.storefront,
                overlay: settings.overlay,
                cache: settings.cacheEnabled ? FileShowcaseCache() : nil
            ).load()
        } catch {
            apps = []
            failure = String(describing: error)
        }
    }
}
