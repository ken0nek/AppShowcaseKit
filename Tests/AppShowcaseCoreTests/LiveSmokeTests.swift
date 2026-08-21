import Foundation
import Testing

@testable import AppShowcaseCore

/// The suite is skipped rather than failed when this is unset, so `swift test`
/// stays green on a machine that has deliberately not opted in.
///
/// File scope, not a static on the suite: a `.enabled(if:)` trait cannot
/// reference the type it is attached to without a circular macro expansion.
private let hostBundleID: String? = ProcessInfo.processInfo
    .environment["SHOWCASE_LIVE_BUNDLE_ID"]

/// Hits the real endpoint. Off by default so the suite stays hermetic and fast;
/// the fixtures carry the day-to-day coverage.
///
/// Point it at any bundle identifier that is live on the App Store — yours, or
/// any app at all. The assertions are structural, so they hold for any
/// developer's roster, including a developer with exactly one published app.
///
/// ```sh
/// SHOWCASE_LIVE_BUNDLE_ID=com.example.YourApp swift test --filter LiveSmoke
/// ```
///
/// Run it when the API might have moved under us — a changed response shape, a
/// dropped field, a new rate limit. That is exactly what the fixtures cannot
/// catch, because they are frozen.
@Suite("LiveSmoke", .enabled(if: hostBundleID != nil))
struct LiveSmokeTests {
    /// The host's own record, straight from step one of the chain.
    ///
    /// Deliberately not read out of the roster: the roster excludes the host, so
    /// anything derived from it is unavailable to a single-app developer. The
    /// identity call always carries the host itself.
    private func identity(_ alpha3: String) async throws -> ShowcaseApp {
        let endpoint = LookupEndpoint.identity(
            bundleID: try #require(hostBundleID), storefront: StorefrontCode(alpha3: alpha3)
        )
        let data = try await URLSessionTransport().data(from: endpoint.url)

        return try #require(
            LookupResponse.decode(data).apps.first,
            "SHOWCASE_LIVE_BUNDLE_ID must name an app that is live in the \(alpha3) storefront"
        )
    }

    private func roster(_ alpha3: String) async throws -> [ShowcaseApp] {
        try await ShowcaseLoader(
            hostBundleID: try #require(hostBundleID),
            storefront: StorefrontCode(alpha3: alpha3),
            // Deliberately absurd, so the OS-floor filter never
            // silently empties the roster and makes this suite vacuous.
            running: .iOS("999.0"),
            cache: nil
        ).load()
    }

    @Test("resolves a real roster from a bundle identifier and nothing else")
    func resolvesRealRoster() async throws {
        let apps = try await roster("USA")

        // A single-app developer is a legitimate answer, so this asserts shape
        // rather than count. What must hold: the chain resolved, the host is
        // excluded from its own roster, and every row is usable.
        #expect(!apps.contains { $0.bundleID == hostBundleID })
        #expect(Set(apps.map(\.artistID)).count <= 1, "one developer, one artistID")
        #expect(apps.allSatisfy { !$0.name.isEmpty })
        #expect(apps.allSatisfy { !$0.minimumOSVersion.isEmpty })
        #expect(apps.allSatisfy { $0.iconURL.absoluteString.hasPrefix("https://") })
        #expect(apps.allSatisfy { $0.storeURL.absoluteString.contains("id\($0.id)") })
    }

    /// Guards the assumption the whole design rests on: that the `country`
    /// parameter really does localize the response rather than being decorative.
    ///
    /// Compares the host's own record across two storefronts, so it needs no
    /// siblings — only that the app is sold in both.
    @Test("returns storefront-localized text")
    func localizesByStorefront() async throws {
        let us = try await identity("USA")
        let jp = try await identity("JPN")

        // Price is the signal that holds: currency differs across these two
        // storefronts even for a developer who ships one untranslated name.
        // ("Free" vs "無料", "$1.99" vs "¥300".)
        #expect(
            us.name != jp.name || us.formattedPrice != jp.formattedPrice,
            "country= is served, not ignored"
        )
    }

    /// Against the live API: the decoder drops any row whose `kind`
    /// it does not recognize, which is the safe direction to fail in but a silent
    /// one: a third `kind` would quietly shrink every roster, everywhere, and a
    /// frozen fixture could never notice. This compares what the API sent against
    /// what survived.
    @Test("every software row still carries a kind this package recognizes")
    func everyRowHasARecognizedKind() async throws {
        let artistID = try await identity("USA").artistID
        let endpoint = LookupEndpoint.roster(
            artistID: artistID, storefront: StorefrontCode(alpha3: "USA")
        )
        let data = try await URLSessionTransport().data(from: endpoint.url)

        struct RawBody: Decodable {
            struct Row: Decodable { let wrapperType: String? }
            let results: [Row]
        }
        let sent = try JSONDecoder().decode(RawBody.self, from: data)
            .results.count { $0.wrapperType == "software" }

        #expect(
            try LookupResponse.decode(data).apps.count == sent,
            "a software row was dropped: the API is returning a `kind` this package does not map"
        )
    }

    /// Against the live API: the fixture proves the parser handles
    /// the missing-entity shape; this proves the API still produces it, which is
    /// the half a frozen capture can never re-verify.
    @Test("the API still answers an entity-less artist lookup with zero apps")
    func missingEntityStillFailsSuccessfully() async throws {
        let artistID = try await identity("USA").artistID

        var components = try #require(URLComponents(string: "https://itunes.apple.com/lookup"))
        components.queryItems = [URLQueryItem(name: "id", value: String(artistID))]

        let data = try await URLSessionTransport().data(from: try #require(components.url))
        let response = try LookupResponse.decode(data)

        #expect(response.reportedCount > 0, "HTTP 200, valid JSON, non-zero count…")
        #expect(response.apps.isEmpty, "…and not one app.")
        #expect(response.looksLikeMissingEntityParameter)
    }
}
