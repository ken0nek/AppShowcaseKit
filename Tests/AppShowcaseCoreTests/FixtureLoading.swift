import Foundation
import Testing

/// Every fixture is a **real, unedited** response captured from
/// `itunes.apple.com/lookup`. They are the evidence base for the failure modes
/// this package encodes, so they are never hand-tweaked to suit a test — recapture them
/// instead. A fixture edited to make a test pass is no longer evidence of
/// anything, and the behavior it documented quietly stops being defended.
enum Fixture: String {
    /// `?id=975026926&entity=software&country=us` — the correct artist call.
    case rosterUS = "artist-roster-us"
    /// The same call against the `jp` storefront: localized names, different
    /// rating counts.
    case rosterJP = "artist-roster-jp"
    /// An artist call against an account that ships to both stores.
    /// Ten iOS apps and five Mac apps arrive in one roster, every one of them
    /// `wrapperType: software`; only `kind` tells them apart, and the Mac rows
    /// report *macOS* version floors, which are numerically lower than any
    /// current iOS version.
    case rosterMixedPlatform = "artist-roster-mixed-platform"
    /// `?bundleId=com.ken0nek.BrewSmart` — step one of the discovery chain.
    case bundleID = "bundleid-brewsmart"
    /// The artist call with `entity=software` omitted. HTTP 200,
    /// well-formed body, `resultCount: 1`, and not one app.
    case noEntity = "artist-no-entity"
    /// `resultCount: 0` — a normal answer, not an error.
    case empty
    case malformed

    var data: Data {
        get throws {
            let url = try #require(
                Bundle.module.url(forResource: rawValue, withExtension: "json"),
                "fixture \(rawValue).json is missing from the test bundle"
            )
            return try Data(contentsOf: url)
        }
    }
}
