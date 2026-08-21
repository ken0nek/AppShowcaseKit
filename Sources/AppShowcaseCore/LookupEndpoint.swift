import Foundation

/// The two lookup requests the discovery chain needs.
///
/// Modeled as a closed enum, not a URL builder, specifically so that callers
/// cannot assemble a request that omits `entity=software` — see ``roster``.
public enum LookupEndpoint: Sendable, Equatable {
    /// Step one: who publishes this app? Answers with the host's own record,
    /// which carries the `artistId` the whole roster hangs off.
    case identity(bundleID: String, storefront: StorefrontCode)

    /// Step two: everything that developer publishes.
    ///
    /// `entity=software` is not optional and is not exposed. Without
    /// it the response is HTTP 200, valid JSON, `resultCount: 1` — the artist
    /// record and not one app. Nothing about that reads as a failure, so a
    /// caller who forgot it ships a permanently empty section and never sees an
    /// error. Making it unforgettable is most of this type's reason to exist.
    case roster(artistID: Int, storefront: StorefrontCode)

    public var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"

        switch self {
        case .identity(let bundleID, let storefront):
            components.queryItems = [
                URLQueryItem(name: "bundleId", value: bundleID),
                URLQueryItem(name: "country", value: storefront.parameterValue),
            ]
        case .roster(let artistID, let storefront):
            components.queryItems = [
                URLQueryItem(name: "id", value: String(artistID)),
                URLQueryItem(name: "entity", value: "software"),
                URLQueryItem(name: "country", value: storefront.parameterValue),
                // The endpoint's own default is 50, which would silently truncate
                // a developer with a large catalog.
                URLQueryItem(name: "limit", value: String(Self.limit)),
            ]
        }

        // Force-unwrap is safe: every component above is a literal or a
        // percent-encodable string, and the two cases are exhaustive.
        return components.url!
    }

    static let limit = 200
}
