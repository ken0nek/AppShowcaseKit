import AppShowcaseCore
import Foundation
import Observation

/// Every knob the two screens share.
///
/// `com.apple.Pages` is the default because its roster is the one that shows the
/// filter doing something: 171 apps, of which 31 are `mac-software` and must
/// never reach an iPhone. A roster containing only iOS apps would look identical
/// whether `RosterResolver` ran or not.
///
/// `SHOWCASE_LIVE_BUNDLE_ID` seeds it when set — the same variable the live
/// smoke suite reads — so this app can be pointed at a private roster without
/// that identifier ever entering the repository.
@Observable
final class InspectorSettings {
    var bundleID: String =
        ProcessInfo.processInfo.environment["SHOWCASE_LIVE_BUNDLE_ID"] ?? "com.apple.Pages"
    var alpha3: String = "USA"
    var tapStyle: ShowcaseTapStyle = .default
    var cacheEnabled: Bool = true
    var excluded: Set<Int> = []

    /// Alpha-3, because that is what `StorefrontCode` takes — StoreKit reports
    /// alpha-3 and the lookup API wants alpha-2, and converting between them is
    /// one of the things this package exists to do. `JPN` is the one worth
    /// trying: it returns Japanese names and yen prices, which is the
    /// wrong-storefront bug made visible on a device that has never left the US.
    static let storefronts = ["USA", "JPN", "GBR", "DEU"]

    var storefront: StorefrontCode { StorefrontCode(alpha3: alpha3) }

    var overlay: ShowcaseOverlay { ShowcaseOverlay(excluded: excluded) }
}
