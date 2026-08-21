import Testing

@testable import AppShowcaseCore

/// The overlay is the whole "optional" half of the design: supply nothing and the
/// kit is pure live discovery; supply a little and you get curation, without ever
/// hand-maintaining the roster itself.
@Suite("ShowcaseOverlay")
struct ShowcaseOverlayTests {
    private func liveRoster() throws -> [ShowcaseApp] {
        try LookupResponse.decode(Fixture.rosterUS.data).apps
    }

    private let firstApp = 6_745_852_921
    private let secondApp = 6_758_604_043
    private let thirdApp = 6_766_441_698
    private let fourthApp = 6_784_029_039

    @Test("an empty overlay changes nothing")
    func emptyOverlayIsInert() throws {
        let roster = try liveRoster()

        let withOverlay = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: .none)
            .resolve(roster)
        let without = RosterResolver(hostAppID: nil, running: .iOS("26.0"))
            .resolve(roster)

        #expect(withOverlay == without)
    }

    /// The API has no subtitle, so this is the *only*
    /// route to the one line of copy that makes a settings row worth tapping.
    @Test("supplies the tagline the API structurally cannot")
    func suppliesTagline() throws {
        var overlay = ShowcaseOverlay()
        overlay.taglines = [secondApp: "Strip the tracking junk off any link"]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        let app = try #require(resolved.first { $0.id == secondApp })
        #expect(app.tagline == "Strip the tracking junk off any link")
        // Apps the overlay says nothing about keep their honest nil.
        #expect(resolved.first { $0.id == fourthApp }?.tagline == nil)
    }

    @Test("drops an app the overlay excludes")
    func excludesApp() throws {
        var overlay = ShowcaseOverlay()
        overlay.excluded = [thirdApp]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        #expect(!resolved.contains { $0.id == thirdApp })
        #expect(resolved.count == 3)
    }

    @Test("pins the order the overlay asks for")
    func pinsOrder() throws {
        var overlay = ShowcaseOverlay()
        overlay.order = [fourthApp, firstApp]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        #expect(resolved.prefix(2).map(\.id) == [fourthApp, firstApp])
    }

    @Test("leaves unpinned apps in the order the API gave them")
    func unpinnedKeepAPIOrder() throws {
        let apiOrder = try liveRoster().map(\.id)
        var overlay = ShowcaseOverlay()
        overlay.order = [fourthApp]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        #expect(resolved.first?.id == fourthApp)
        #expect(resolved.dropFirst().map(\.id) == apiOrder.filter { $0 != fourthApp })
    }

    /// Ken ships app #5 and forgets to update a pin list written months earlier.
    /// The new app must still appear, not vanish because it went unmentioned.
    @Test("shows an app the pin list has never heard of")
    func pinListDoesNotActAsAnAllowlist() throws {
        var overlay = ShowcaseOverlay()
        overlay.order = [fourthApp]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        #expect(resolved.count == 4)
    }

    /// A stale pin naming a delisted app must not resurrect it or crash the sort.
    @Test("ignores a pinned id that is not in the roster")
    func ignoresStalePin() throws {
        var overlay = ShowcaseOverlay()
        overlay.order = [9_999_999_999, fourthApp]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        #expect(resolved.count == 4)
        #expect(resolved.first?.id == fourthApp)
    }

    /// A pin list edited over several releases can easily name an app twice. That
    /// must reorder nothing and, above all, must not take the process down.
    @Test("survives a pin list that names the same app twice")
    func repeatedPinDoesNotTrap() throws {
        var overlay = ShowcaseOverlay()
        overlay.order = [fourthApp, secondApp, fourthApp]

        let resolved = RosterResolver(hostAppID: nil, running: .iOS("26.0"), overlay: overlay)
            .resolve(try liveRoster())

        // The repeat keeps its earliest position; everything unpinned holds the
        // order the API returned.
        #expect(resolved.map(\.id) == [fourthApp, secondApp, firstApp, thirdApp])
    }
}
