import Foundation

/// A decoded `itunes.apple.com/lookup` body.
public struct LookupResponse: Sendable, Equatable {
    /// The API's own `resultCount`. Kept separately from `apps.count` because
    /// the difference between them is diagnostic — see
    /// ``looksLikeMissingEntityParameter``.
    public let reportedCount: Int

    /// Rows that are actually apps. An artist lookup always prepends an `artist`
    /// record, which is not one.
    public let apps: [ShowcaseApp]

    /// An artist lookup without `entity=software` returns HTTP 200,
    /// valid JSON, `resultCount: 1` — the artist record and not one app. Nothing
    /// about it reads as a failure, so the bug ships and the section is empty
    /// forever.
    ///
    /// A non-zero count carrying no software is the tell. Distinguishing it from
    /// an honestly-empty storefront (`resultCount: 0`) is the difference between
    /// "fix your URL" and "nothing to show here".
    public var looksLikeMissingEntityParameter: Bool {
        reportedCount > 0 && apps.isEmpty
    }

    public static func decode(_ data: Data) throws -> LookupResponse {
        let body = try JSONDecoder().decode(Body.self, from: data)
        return LookupResponse(
            reportedCount: body.resultCount,
            apps: body.results.compactMap(\.asShowcaseApp)
        )
    }
}

// MARK: - Wire shape

private struct Body: Decodable {
    let resultCount: Int
    let results: [Row]
}

/// Every field is optional because one response mixes shapes: the `artist` row
/// carries almost none of these. Filtering happens in ``asShowcaseApp``, not in
/// the decoder, so a malformed app row is dropped rather than failing the whole
/// roster.
private struct Row: Decodable {
    let wrapperType: String?
    /// `software` or `mac-software`. `wrapperType` says `software`
    /// for both, so this is the only field that tells an iPhone app from a Mac
    /// app in a roster that contains both.
    let kind: String?
    let trackId: Int?
    let artistId: Int?
    let trackName: String?
    let bundleId: String?
    let primaryGenreName: String?
    let formattedPrice: String?
    let minimumOsVersion: String?
    let artworkUrl512: String?
    let trackViewUrl: String?

    var asShowcaseApp: ShowcaseApp? {
        guard wrapperType == "software",
            let platform = ShowcasePlatform(kind: kind),
            let trackId, let artistId, let trackName, let bundleId,
            let primaryGenreName, let minimumOsVersion,
            let iconURL = artworkUrl512.flatMap(URL.init(string:)),
            let storeURL = trackViewUrl.flatMap(URL.init(string:))
        else { return nil }

        return ShowcaseApp(
            id: trackId,
            artistID: artistId,
            name: trackName,
            bundleID: bundleId,
            genre: primaryGenreName,
            formattedPrice: formattedPrice,
            platform: platform,
            minimumOSVersion: minimumOsVersion,
            iconURL: iconURL,
            storeURL: storeURL
                // tagline stays nil — the API has no subtitle to give.
        )
    }
}
