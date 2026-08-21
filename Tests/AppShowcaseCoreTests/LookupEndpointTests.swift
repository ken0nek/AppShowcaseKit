import Foundation
import Testing

@testable import AppShowcaseCore

@Suite("LookupEndpoint")
struct LookupEndpointTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { _, b in
            b
        }
    }

    /// At its source: omitting `entity=software` returns HTTP 200,
    /// valid JSON, `resultCount: 1` and zero apps. The bug is unobservable at the
    /// call site, so the parameter must be impossible to forget — it is baked in
    /// here rather than passed by callers.
    @Test("always sends entity=software on an artist lookup")
    func alwaysSendsEntitySoftware() {
        let url = LookupEndpoint.roster(
            artistID: 1_234_567_890, storefront: StorefrontCode(alpha3: "USA")
        ).url

        #expect(query(url)["entity"] == "software")
    }

    @Test("sends the storefront as alpha-2")
    func sendsAlpha2Storefront() {
        let url = LookupEndpoint.roster(
            artistID: 1_234_567_890, storefront: StorefrontCode(alpha3: "JPN")
        ).url

        #expect(query(url)["country"] == "jp")
    }

    @Test("asks for the artist by id")
    func sendsArtistID() {
        let url = LookupEndpoint.roster(
            artistID: 1_234_567_890, storefront: StorefrontCode(alpha3: "USA")
        ).url

        #expect(query(url)["id"] == "1234567890")
    }

    /// The default `limit` is 50, which silently truncates a prolific developer.
    @Test("raises the limit above the default that would truncate a big roster")
    func raisesLimit() {
        let url = LookupEndpoint.roster(
            artistID: 1_234_567_890, storefront: StorefrontCode(alpha3: "USA")
        ).url

        #expect(Int(query(url)["limit"] ?? "0") ?? 0 >= 200)
    }

    @Test("looks the host app up by bundle identifier to start the chain")
    func buildsBundleIDLookup() {
        let url = LookupEndpoint.identity(
            bundleID: "com.example.NoteJar", storefront: StorefrontCode(alpha3: "USA")
        ).url

        #expect(query(url)["bundleId"] == "com.example.NoteJar")
        #expect(query(url)["country"] == "us")
    }

    @Test("targets the lookup endpoint over https")
    func targetsLookupEndpoint() {
        let url = LookupEndpoint.roster(artistID: 1, storefront: StorefrontCode(alpha3: "USA")).url

        #expect(url.scheme == "https")
        #expect(url.host() == "itunes.apple.com")
        #expect(url.path() == "/lookup")
    }
}
