import AppShowcaseCore
import Foundation
import Testing

@testable import AppShowcaseStoreKit

private struct FailingTransport: LookupTransport {
    func data(from url: URL) async throws -> Data { throw LookupError.transportFailed }
}

private struct CancellingTransport: LookupTransport {
    func data(from url: URL) async throws -> Data { throw CancellationError() }
}

private struct NoResultsTransport: LookupTransport {
    func data(from url: URL) async throws -> Data {
        Data(#"{"resultCount":0,"results":[]}"#.utf8)
    }
}

private actor SeededCache: ShowcaseCache {
    private let seeded: ShowcaseCacheEntry

    init(_ entry: ShowcaseCacheEntry) { seeded = entry }

    func entry(for key: ShowcaseCacheKey) async -> ShowcaseCacheEntry? { seeded }
    func store(_ entry: ShowcaseCacheEntry, for key: ShowcaseCacheKey) async {}
}

private actor CountingFailingTransport: LookupTransport {
    private var count = 0

    func data(from url: URL) async throws -> Data {
        count += 1
        throw LookupError.transportFailed
    }

    func calls() -> Int { count }
}

@Suite("resolved")
struct ResolvedRosterTests {
    private func resolution(
        _ transport: any LookupTransport, cache: (any ShowcaseCache)? = nil
    ) async -> ShowcaseResolution {
        await ShowcaseLoader.resolution(
            transport: transport,
            hostBundleID: "com.example.NoteJar",
            storefront: StorefrontCode(alpha3: "USA"),
            overlay: .none,
            cache: cache
        )
    }

    @Test("answers empty instead of throwing when the lookup fails")
    func silentOnFailure() async {
        let apps = await ShowcaseLoader.resolved(
            transport: FailingTransport(),
            hostBundleID: "com.example.NoteJar",
            storefront: StorefrontCode(alpha3: "USA"),
            overlay: .none,
            cache: nil
        )
        #expect(apps.isEmpty)
    }

    @Test("answers empty for a cancelled load, the same as for a roster with nothing in it")
    func cancelledLoadReadsAsEmpty() async {
        let apps = await ShowcaseLoader.resolved(
            transport: CancellingTransport(),
            hostBundleID: "com.example.NoteJar",
            storefront: StorefrontCode(alpha3: "USA"),
            overlay: .none,
            cache: nil
        )
        #expect(apps.isEmpty)
    }

    /// The point of the override: an extension's own identifier is not on the
    /// App Store, so the identifier that reaches the endpoint has to be the one
    /// the host named rather than the one it is running under.
    @Test("prefers an overridden bundle identifier over the running bundle")
    func overrideBundleIDBeatsTheRunningBundle() {
        let host = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(bundleID: "com.apple.Pages"),
            environmentBundleID: "com.example.AppShowcaseKitExampleiOS",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.bundleID == "com.apple.Pages")
    }

    @Test("prefers an overridden storefront over the device's own")
    func overrideStorefrontBeatsTheDeviceStorefront() {
        let host = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(storefront: StorefrontCode(alpha3: "JPN")),
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.storefront.parameterValue == "jp")
    }

    /// A `nil` field means *read the environment*, not *use an empty value*.
    /// Overriding only the identifier is the common case, and a storefront
    /// silently reset to a default would serve a US roster to a Japanese user —
    /// the wrong-storefront bug, arriving through the fix for a different one.
    @Test("falls back to the environment for whichever field is not overridden")
    func unsetFieldsFallBackToTheEnvironment() {
        let partial = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(bundleID: "com.apple.Pages"),
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "JPN")
        )

        #expect(partial.bundleID == "com.apple.Pages")
        #expect(partial.storefront.parameterValue == "jp", "the storefront was not overridden")

        let neither = ShowcaseLoader.effectiveHost(
            override: .none,
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(neither.bundleID == "com.example.NoteJar")
        #expect(neither.storefront.parameterValue == "us")
    }

    /// The same absence, arriving as an empty string rather than as `nil` —
    /// what a host binding the field to a text field writes the moment the user
    /// clears it. `bundleId=` is a lookup whose only possible answer is
    /// `hostAppNotFound`, so a cleared field reads as *use the running bundle*.
    @Test("treats an emptied override as absent rather than as a value")
    func emptyOverrideFallsBackToTheEnvironment() {
        let host = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(bundleID: ""),
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.bundleID == "com.example.NoteJar")
    }

    /// A host with no bundle identifier at all — the `?? ""` arm. It resolves to
    /// `hostAppNotFound` rather than crashing, which is the behavior that
    /// existed before the override and must survive it.
    @Test("survives a host with no bundle identifier")
    func missingEnvironmentIdentifierIsEmptyRatherThanFatal() {
        let host = ShowcaseLoader.effectiveHost(
            override: .none,
            environmentBundleID: nil,
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.bundleID.isEmpty)
    }

    @Test("reports a cancelled load as unfinished")
    func cancellationIsUnfinished() async {
        #expect(await resolution(CancellingTransport()) == .unfinished)
    }

    @Test("reports a network failure with nothing cached as unfinished")
    func transportFailureWithNothingCachedIsUnfinished() async {
        #expect(await resolution(FailingTransport()) == .unfinished)
    }

    @Test("reports a host that is not on the store as an answer, not as something to retry")
    func unlistedHostIsAnAnswer() async {
        #expect(await resolution(NoResultsTransport()) == .roster([]))
    }

    @Test("reports a stale roster served over a network failure as an answer")
    func staleRosterIsAnAnswer() async {
        let sibling = ShowcaseApp(
            id: 2,
            artistID: 9,
            name: "Note Jar",
            bundleID: "com.example.NoteJar2",
            genre: "Productivity",
            formattedPrice: "Free",
            platform: RunningOS.current.platform,
            minimumOSVersion: "1.0",
            iconURL: URL(string: "https://example.com/icon.png")!,
            storeURL: URL(string: "https://apps.apple.com/us/app/id2")!
        )
        let cache = SeededCache(
            ShowcaseCacheEntry(hostAppID: 1, apps: [sibling], storedAt: .distantPast)
        )

        #expect(await resolution(FailingTransport(), cache: cache) == .roster([sibling]))
    }

    @Test("returns the cached roster, with the overlay applied, without touching the network")
    func returnsTheResolvedRosterOnSuccess() async {
        func app(_ id: Int) -> ShowcaseApp {
            ShowcaseApp(
                id: id,
                artistID: 9,
                name: "App \(id)",
                bundleID: "com.example.app\(id)",
                genre: "Productivity",
                formattedPrice: "Free",
                platform: RunningOS.current.platform,
                minimumOSVersion: "1.0",
                iconURL: URL(string: "https://example.com/\(id).png")!,
                storeURL: URL(string: "https://apps.apple.com/us/app/id\(id)")!
            )
        }
        let cache = SeededCache(
            ShowcaseCacheEntry(hostAppID: 1, apps: [app(1), app(2)], storedAt: Date())
        )
        let transport = CountingFailingTransport()

        let apps = await ShowcaseLoader.resolved(
            transport: transport,
            hostBundleID: "com.example.NoteJar",
            storefront: StorefrontCode(alpha3: "USA"),
            overlay: ShowcaseOverlay(taglines: [2: "A line"]),
            cache: cache
        )

        #expect(apps.map(\.id) == [2])
        #expect(apps.first?.tagline == "A line")
        #expect(await transport.calls() == 0)
    }
}
