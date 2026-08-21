import Foundation
import Testing

@testable import AppShowcaseCore

@Suite("ShowcaseTapStyle")
struct ShowcaseTapStyleTests {
    @Test("defaults to the in-app store sheet")
    func defaultsToStoreSheet() {
        #expect(ShowcaseTapStyle.default == .storeSheet)
    }

    /// Two of the three keep the user inside your app. If a fourth is ever added
    /// that leaves, this test is where someone notices.
    @Test("knows which styles background the host app")
    func knowsWhichStylesLeave() {
        #expect(ShowcaseTapStyle.storeSheet.leavesApp == false)
        #expect(ShowcaseTapStyle.overlay.leavesApp == false)
        #expect(ShowcaseTapStyle.storeLink.leavesApp == true)
    }

    @Test("is round-trippable so a host can persist the choice")
    func isCodable() throws {
        for style in ShowcaseTapStyle.allCases {
            let data = try JSONEncoder().encode(style)
            #expect(try JSONDecoder().decode(ShowcaseTapStyle.self, from: data) == style)
        }
    }
}

@Suite("ShowcaseAttribution")
struct ShowcaseAttributionTests {
    /// The `?uo=4` is not decorative — every `trackViewUrl` the API returns
    /// carries it, so decoration has to append to the query rather than replace
    /// it. That is the shape this URL exists to reproduce.
    private let storeURL = URL(
        string: "https://apps.apple.com/us/app/note-jar/id1234567890?uo=4")!

    @Test("adds the campaign parameters App Analytics reads")
    func decoratesStoreURL() throws {
        let attribution = ShowcaseAttribution(
            providerToken: "1234567", campaignToken: "showcase-notejar")

        let decorated = attribution.decorating(storeURL)
        let items = try #require(
            URLComponents(url: decorated, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.contains(URLQueryItem(name: "pt", value: "1234567")))
        #expect(items.contains(URLQueryItem(name: "ct", value: "showcase-notejar")))
        #expect(items.contains(URLQueryItem(name: "mt", value: "8")))
    }

    @Test("keeps the query parameters Apple already put on the URL")
    func preservesExistingQuery() throws {
        let decorated = ShowcaseAttribution(providerToken: "1234567", campaignToken: "c")
            .decorating(storeURL)
        let items = try #require(
            URLComponents(url: decorated, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.contains(URLQueryItem(name: "uo", value: "4")))
    }

    /// Attribution is optional by design — it is the one value the kit cannot
    /// derive from the device. Without it the link must still work.
    @Test("returns the URL untouched when there is nothing to attribute")
    func isInertWithoutTokens() {
        #expect(ShowcaseAttribution.none.decorating(storeURL) == storeURL)
    }

    /// A campaign token with no provider token is silently ignored by App
    /// Analytics, so emitting it would only look like it worked.
    @Test("does not decorate on a campaign token alone")
    func requiresProviderToken() {
        let attribution = ShowcaseAttribution(providerToken: nil, campaignToken: "showcase-x")

        #expect(attribution.decorating(storeURL) == storeURL)
    }

    @Test("builds a campaign token that names the host app")
    func derivesCampaignTokenFromHost() {
        let attribution = ShowcaseAttribution(
            providerToken: "1234567", hostBundleID: "com.example.NoteJar")

        #expect(attribution.campaignToken == "showcase-notejar")
    }
}
