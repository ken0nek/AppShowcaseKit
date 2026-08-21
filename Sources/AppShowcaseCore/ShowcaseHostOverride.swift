import Foundation

/// Identifies the host to the lookup API when the running bundle is not the one
/// on the App Store.
///
/// The default path needs none of this: `Bundle.main.bundleIdentifier` and the
/// device's own storefront are the right answers for an app resolving its
/// developer's roster. Three hosts where they are not:
///
/// - **An app extension.** A widget or share extension has its own identifier —
///   `com.example.App.Widget` — and that identifier is not on the App Store at
///   all. The lookup returns no results, the chain ends at `hostAppNotFound`,
///   and the section renders empty with no way to say why.
/// - **A Catalyst variant, or a renamed app**, whose store listing sits under an
///   identifier the running binary does not carry.
/// - **A diagnostic harness** pointing the kit at a roster it does not own.
///
/// **This is host identity, and that is its entire remit.** It is not a
/// configuration object and nothing cosmetic belongs on it — no tint, no font,
/// no string, no row layout. The supported answer to "I want different rows" is
/// `AppShowcaseCore` plus your own view.
///
/// Both fields are optional, and `nil` means *read the environment* rather than
/// *use an empty value*. Overriding the identifier while keeping the device's
/// real storefront is the common case, and a non-optional field would force a
/// caller to invent a storefront it has no opinion about.
public struct ShowcaseHostOverride: Sendable, Equatable {
    /// The identifier to look up, in place of `Bundle.main.bundleIdentifier`.
    public var bundleID: String?

    /// The storefront to query, in place of the device's own.
    public var storefront: StorefrontCode?

    public init(bundleID: String? = nil, storefront: StorefrontCode? = nil) {
        self.bundleID = bundleID
        self.storefront = storefront
    }

    /// Override nothing — the default everywhere, and what every caller that has
    /// never heard of this type gets.
    public static let none = ShowcaseHostOverride()
}
