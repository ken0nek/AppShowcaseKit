import Foundation
import Testing

@testable import AppShowcaseCore

/// Records every URL it is asked for and replies from the captured fixtures, so
/// the whole two-call chain is exercised without a network.
private actor RecordingTransport: LookupTransport {
    private(set) var requested: [URL] = []
    private let replies: [Data]
    private var index = 0

    init(replies: [Data]) { self.replies = replies }

    func data(from url: URL) async throws -> Data {
        requested.append(url)
        defer { index += 1 }
        guard index < replies.count else { throw LookupError.transportFailed }
        return replies[index]
    }

    func requestedURLs() -> [URL] { requested }
}

private struct FailingTransport: LookupTransport {
    func data(from _: URL) async throws -> Data { throw LookupError.transportFailed }
}

@Suite("ShowcaseLoader")
struct ShowcaseLoaderTests {
    private let hostApp = 6_745_852_921

    /// `cache: nil` throughout. The default cache is a real directory under
    /// `Caches/`, which would leak state between these tests and between runs —
    /// the two-call assertions below would see zero calls on a second run.
    /// Caching has its own suite, against a temporary directory.
    private func loader(
        _ transport: any LookupTransport,
        bundleID: String = "com.ken0nek.BrewSmart",
        os: String = "26.0",
        overlay: ShowcaseOverlay = .none
    ) -> ShowcaseLoader {
        ShowcaseLoader(
            transport: transport,
            hostBundleID: bundleID,
            storefront: StorefrontCode(alpha3: "USA"),
            running: .iOS(os),
            overlay: overlay,
            cache: nil
        )
    }

    @Test("resolves the roster from nothing but the host's own bundle identifier")
    func resolvesFromBundleIDAlone() async throws {
        let transport = RecordingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])

        let apps = try await loader(transport).load()

        // Four in the roster, minus the host itself.
        #expect(apps.count == 3)
        #expect(!apps.contains { $0.id == hostApp })
    }

    @Test("asks who publishes this app, then what else they publish")
    func makesTheTwoCallChain() async throws {
        let transport = RecordingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])

        _ = try await loader(transport).load()
        let urls = await transport.requestedURLs()

        #expect(urls.count == 2)
        #expect(urls[0].absoluteString.contains("bundleId=com.ken0nek.BrewSmart"))
        // The artistId is discovered from reply one, never hardcoded.
        #expect(urls[1].absoluteString.contains("id=975026926"))
    }

    /// End to end: the chain must never issue an artist lookup
    /// without `entity=software`.
    @Test("never issues the roster call without entity=software")
    func rosterCallAlwaysCarriesEntity() async throws {
        let transport = RecordingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])

        _ = try await loader(transport).load()
        let urls = await transport.requestedURLs()

        #expect(urls[1].absoluteString.contains("entity=software"))
    }

    /// If someone ever reintroduces the bug, the loader must say so rather than
    /// hand back a plausible empty roster.
    @Test("reports the missing-entity signature instead of an innocent empty list")
    func surfacesTheMissingEntitySignature() async throws {
        let transport = RecordingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.noEntity.data,
        ])

        await #expect(throws: LookupError.rosterMissingEntityParameter) {
            try await loader(transport).load()
        }
    }

    /// TestFlight-only or unreleased: the host is not on the store, so there is
    /// no artistId to chain from and nothing to show.
    @Test("throws a distinct error when the host app is not on the App Store")
    func handlesUnlistedHost() async throws {
        let transport = RecordingTransport(replies: [try Fixture.empty.data])

        await #expect(throws: LookupError.hostAppNotFound) {
            try await loader(transport).load()
        }
    }

    @Test("propagates a transport failure rather than pretending the roster is empty")
    func propagatesTransportFailure() async {
        await #expect(throws: LookupError.transportFailed) {
            try await loader(FailingTransport()).load()
        }
    }

    @Test("applies the overlay to what it loads")
    func appliesOverlay() async throws {
        let transport = RecordingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])
        let overlay = ShowcaseOverlay(taglines: [6_784_029_039: "Watch numbers dance"])

        let apps = try await loader(transport, overlay: overlay).load()

        #expect(apps.first { $0.id == 6_784_029_039 }?.tagline == "Watch numbers dance")
    }

    /// Not hypothetical: in this fixture the host is the only app that ships to
    /// iOS 18, so a user on iOS 18 has nothing installable to show. An empty
    /// roster is the correct answer, not a failure.
    @Test("returns nothing rather than dead-end rows on an older OS")
    func filtersEverythingOnAnOlderOS() async throws {
        let transport = RecordingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])

        let apps = try await loader(transport, os: "18.0").load()

        #expect(apps.isEmpty)
    }
}
