import Testing

@testable import AppShowcaseCore

@Suite("RosterResolver")
struct RosterResolverTests {
    /// Four apps as the live API actually returned them. The
    /// first requires iOS 18.0; the other three require 26.0 — which is what
    /// makes the OS-floor filter testable against real data.
    private func liveRoster() throws -> [ShowcaseApp] {
        try LookupResponse.decode(Fixture.rosterUS.data).apps
    }

    private let hostApp = 6_745_852_921

    /// An artist lookup always includes the caller. Left in, every
    /// app lists itself in its own "more from me" section.
    @Test("excludes the host app from its own showcase")
    func excludesHostApp() throws {
        let resolved = RosterResolver(hostAppID: hostApp, running: .iOS("26.0"))
            .resolve(try liveRoster())

        #expect(!resolved.contains { $0.id == hostApp })
        #expect(resolved.count == 3)
    }

    /// Not hypothetical — this is a real roster spanning two OS
    /// floors. The host ships to iOS 18; its three siblings require 26.
    /// Unfiltered, every one of the host's iOS 18 users sees three rows that
    /// dead-end.
    @Test("hides apps the running OS cannot install")
    func filtersByMinimumOSVersion() throws {
        let resolved = RosterResolver(hostAppID: hostApp, running: .iOS("18.0"))
            .resolve(try liveRoster())

        #expect(resolved.isEmpty)
    }

    /// String comparison puts "9.0" *above* "18.0". A lexicographic compare here
    /// would show an iOS 9 device apps requiring iOS 26.
    @Test("compares OS versions numerically, not lexicographically")
    func comparesVersionsNumerically() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .iOS("9.0"))
            .resolve(try liveRoster())

        #expect(resolved.isEmpty)
    }

    @Test("keeps an app whose floor exactly matches the running OS")
    func treatsTheFloorAsInclusive() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .iOS("18.0"))
            .resolve(try liveRoster())

        #expect(resolved.map(\.id) == [hostApp])
    }

    /// A roster from an account that ships to both stores. Ten iOS apps, five Mac
    /// apps, one `wrapperType` between them.
    private func mixedRoster() throws -> [ShowcaseApp] {
        try LookupResponse.decode(Fixture.rosterMixedPlatform.data).apps
    }

    /// The five Mac apps here declare floors of macOS 11 and 12.
    /// Against a running iOS 18.4 those numbers all read as "comfortably old
    /// enough", so the OS-floor filter — the one guard that exists to stop
    /// dead-end rows — passes every one of them straight through to an iPhone.
    @Test("hides Mac apps from an iOS device")
    func filtersOutOtherPlatforms() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .iOS("18.4"))
            .resolve(try mixedRoster())

        #expect(resolved.allSatisfy { $0.platform == .iOS })
        // Nine of the ten iOS apps; the tenth requires iOS 26.
        #expect(resolved.count == 9)
    }

    /// The same mistake in the other direction, and the one a Mac host would hit:
    /// three of the iOS apps declare floors at or below macOS 14.
    @Test("hides iOS apps from a Mac")
    func filtersOutOtherPlatformsOnMac() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .macOS("14.0"))
            .resolve(try mixedRoster())

        #expect(resolved.allSatisfy { $0.platform == .macOS })
        #expect(resolved.count == 5)
    }

    /// Platform is checked before the version, never instead of it: a Mac app
    /// newer than the running macOS still has to be filtered on its floor.
    @Test("still applies the OS floor within the matching platform")
    func appliesVersionFloorWithinPlatform() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .macOS("11.0"))
            .resolve(try mixedRoster())

        #expect(resolved.count == 2, "only the two apps with a macOS 11 floor")
    }

    @Test("keeps the whole roster when nothing is excluded")
    func keepsEverythingWhenUnconstrained() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"))
            .resolve(try liveRoster())

        #expect(resolved.count == 4)
    }

    @Test("handles a point release above the floor")
    func handlesPointReleases() throws {
        let resolved = RosterResolver(hostAppID: nil, running: .iOS("18.4.1"))
            .resolve(try liveRoster())

        #expect(resolved.map(\.id) == [hostApp])
    }
}
