import Foundation

/// One app in the showcase.
///
/// Everything here except ``tagline`` comes from the lookup API and is already
/// localized to the caller's storefront. ``tagline`` never can — see below.
public struct ShowcaseApp: Sendable, Equatable, Identifiable, Codable {
    /// The App Store ID (`trackId`). Also what every presenter needs to open it.
    public let id: Int
    /// Shared by every app from one developer — the whole roster hangs off it.
    public let artistID: Int
    /// Storefront-localized. In `jp` this is the Japanese name, not a translation
    /// of the US one.
    public let name: String
    public let bundleID: String
    /// `primaryGenreName`, storefront-localized.
    public let genre: String
    /// Pre-formatted in the storefront's currency — "Free", "無料", "¥300".
    /// Never build this yourself from `price`. The API has already done the
    /// currency and locale work.
    public let formattedPrice: String?
    /// Which store sells this app. Read it before ``minimumOSVersion``
    /// means anything: the two floors are on different number lines, and a Mac
    /// app's is always the lower-looking one.
    public let platform: ShowcasePlatform
    /// Compare against the running OS before showing the row, or a
    /// user taps through to an app their device cannot install. Only meaningful
    /// against a running OS of the same ``platform``.
    public let minimumOSVersion: String
    public let iconURL: URL
    public let storeURL: URL

    /// The lookup response has **no `subtitle` field** — 44 keys, and
    /// the App Store subtitle is not among them. This is always `nil` off the
    /// wire. A ``ShowcaseOverlay`` is the only thing that can fill it.
    public var tagline: String?

    public init(
        id: Int,
        artistID: Int,
        name: String,
        bundleID: String,
        genre: String,
        formattedPrice: String?,
        platform: ShowcasePlatform,
        minimumOSVersion: String,
        iconURL: URL,
        storeURL: URL,
        tagline: String? = nil
    ) {
        self.id = id
        self.artistID = artistID
        self.name = name
        self.bundleID = bundleID
        self.genre = genre
        self.formattedPrice = formattedPrice
        self.platform = platform
        self.minimumOSVersion = minimumOSVersion
        self.iconURL = iconURL
        self.storeURL = storeURL
        self.tagline = tagline
    }
}
