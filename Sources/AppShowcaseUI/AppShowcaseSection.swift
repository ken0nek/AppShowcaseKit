import AppShowcaseCore
import AppShowcaseStoreKit
import SwiftUI

/// A Settings section listing the other apps by the same developer.
///
/// Zero configuration in the cosmetic sense: no colors, no fonts, no strings.
/// It inherits the host's `List` styling entirely, and the only text it displays
/// comes from the App Store, already localized to the user's storefront. If you
/// want rows that match your own design system, use `AppShowcaseCore` directly
/// and draw your own — that is the supported path, not a workaround.
///
/// ```swift
/// AppShowcaseSection {
///     Text("More from me")          // your string, your catalog
/// }
/// ```
///
/// Renders nothing at all when there is nothing installable to show, so it can be
/// placed unconditionally.
public struct AppShowcaseSection<Header: View>: View {
    private let tapStyle: ShowcaseTapStyle
    private let attribution: ShowcaseAttribution
    private let overlay: ShowcaseOverlay
    private let onSelect: @MainActor (ShowcaseApp) -> Void
    private let header: Header

    @State private var apps: [ShowcaseApp] = []

    /// Which identity the rows on screen were fetched for.
    ///
    /// Each branch of `body` carries its own reload task, and the roster filling
    /// swaps one branch for the other — so a task is destroyed and a fresh one
    /// created on that transition alone, which would fetch twice on every cold
    /// launch. This records what actually landed, so the new task fetches only
    /// when the identity really did change.
    @State private var loadedOverride: ShowcaseHostOverride?

    /// Defaults to overriding nothing, so a host that never sets it resolves
    /// from `Bundle.main` and pays nothing for the override existing.
    @Environment(\.showcaseHostOverride) private var hostOverride

    /// - Parameters:
    ///   - tapStyle: How a tapped row opens the store. Defaults to the in-app
    ///     product sheet.
    ///   - attribution: Campaign tokens, so App Analytics can attribute installs.
    ///     Without them everything still works, unmeasured.
    ///   - overlay: Optional curation — taglines, order, exclusions.
    ///   - onSelect: Called with the tapped app, before the store is presented.
    ///     For the host's own analytics — the kit reports the tap and names no
    ///     event, because an event taxonomy belongs to the app that has one.
    public init(
        tapStyle: ShowcaseTapStyle = .default,
        attribution: ShowcaseAttribution = .none,
        overlay: ShowcaseOverlay = .none,
        onSelect: @escaping @MainActor (ShowcaseApp) -> Void = { _ in },
        @ViewBuilder header: () -> Header
    ) {
        self.tapStyle = tapStyle
        self.attribution = attribution
        self.overlay = overlay
        self.onSelect = onSelect
        self.header = header()
    }

    public var body: some View {
        // An empty roster means the section vanishes rather than showing a
        // header over nothing.
        if !apps.isEmpty {
            Section {
                ForEach(apps) { app in
                    ShowcaseRow(
                        app: app, tapStyle: tapStyle, attribution: attribution,
                        onSelect: onSelect
                    )
                }
            } header: {
                header
            }
            // On the `Section`, not on a row inside it. A row would work and
            // is the obvious spelling, but `List` gives every row a minimum
            // height — a `Color.clear.frame(height: 0)` measures 52 pt on a
            // device — so an invisible loader row opens a visible gap between
            // the header and the first app.
            .task(id: hostOverride) { await load() }
        } else {
            placeholder
        }
    }

    /// Stands in for the section while there is nothing to show, and carries the
    /// load that fills it.
    ///
    /// This is a real row as far as the enclosing `List` is concerned, so it has
    /// to be stripped of everything that makes a row visible. Left plain, it
    /// contributes default insets and a separator — a stray hairline before the
    /// roster loads, and a permanent one for a single-app developer or a user
    /// whose OS floor filters everything out — which would make "place it
    /// unconditionally" bad advice. Stripped, it still occupies the minimum row
    /// height, which costs an empty screen nothing visible.
    private var placeholder: some View {
        Color.clear
            .frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
            .task(id: hostOverride) { await load() }
    }

    private func load() async {
        guard loadedOverride != hostOverride else { return }
        let override = hostOverride
        // Silent by design. A Settings screen never tells a user that a
        // cross-promotion failed to load.
        apps = await ShowcaseLoader.resolved(overlay: overlay, override: override)
        loadedOverride = override
    }
}

extension AppShowcaseSection where Header == EmptyView {
    /// Headerless — for hosts that supply their own section chrome.
    public init(
        tapStyle: ShowcaseTapStyle = .default,
        attribution: ShowcaseAttribution = .none,
        overlay: ShowcaseOverlay = .none,
        onSelect: @escaping @MainActor (ShowcaseApp) -> Void = { _ in }
    ) {
        self.init(
            tapStyle: tapStyle, attribution: attribution, overlay: overlay, onSelect: onSelect
        ) { EmptyView() }
    }
}

// MARK: - Row

private struct ShowcaseRow: View {
    let app: ShowcaseApp
    let tapStyle: ShowcaseTapStyle
    let attribution: ShowcaseAttribution
    let onSelect: @MainActor (ShowcaseApp) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    /// `@ScaledMetric` is unbounded and takes 40 pt past 75 at the largest
    /// accessibility sizes. The icon scales so it does not look stranded beside
    /// tripled text, not so it becomes the row.
    private var clampedIconSize: CGFloat { min(iconSize, 60) }

    var body: some View {
        Button {
            // Before, not after. `.storeLink` backgrounds the host app, and a
            // host that records the tap in `onSelect` would be recording it
            // during the transition out — the one ordering in this file that a
            // caller cannot fix from the outside.
            onSelect(app)
            tapStyle.makePresenter().present(app, attribution: attribution)
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                // The chip drops below rather than competing for a line it
                // cannot win. `maxWidth: .infinity` keeps the row's tap target
                // full-width, which the Spacer does in the other branch.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        icon
                        titles
                    }
                    priceChip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    icon
                    titles
                    Spacer(minLength: 8)
                    priceChip
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Extracted only so the two layouts above share one definition — a second
    /// copy is a second place for the tagline fallback to drift.
    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app.name)
            // The tagline can only come from an overlay — the API has no
            // subtitle field. Genre is the honest fallback, and it is
            // already storefront-localized.
            Text(app.tagline ?? app.genre)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: some View {
        AsyncImage(url: app.iconURL) { image in
            image.resizable()
        } placeholder: {
            // 0.225 is the ratio the constants here already expressed — 9 over
            // 40 — so at the default type size the row renders as it did before.
            RoundedRectangle(cornerRadius: clampedIconSize * 0.225, style: .continuous)
                .fill(.quaternary)
        }
        .frame(width: clampedIconSize, height: clampedIconSize)
        .clipShape(RoundedRectangle(cornerRadius: clampedIconSize * 0.225, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The store affordance the icon has to sit next to. Its label is Apple's own
    /// `formattedPrice` — already in the storefront's language and currency —
    /// which is how this satisfies the Search API's badge-proximity rule without
    /// the package owning or localizing a single string.
    ///
    /// Because the Search API's terms require it beside the icon, it is the
    /// element in this row least able to be unreadable — and a tint-on-tint
    /// pairing is only ever as legible as an accent color this package does not
    /// choose. So it draws in the same neutral fill the icon placeholder uses.
    @ViewBuilder
    private var priceChip: some View {
        if let price = app.formattedPrice {
            Text(price)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.primary)
        }
    }
}
