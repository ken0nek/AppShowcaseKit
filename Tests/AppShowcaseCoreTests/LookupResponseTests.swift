import Foundation
import Testing

@testable import AppShowcaseCore

@Suite("LookupResponse")
struct LookupResponseTests {
    @Test("decodes the live artist roster into the four shipped apps")
    func decodesRoster() throws {
        let apps = try LookupResponse.decode(Fixture.rosterUS.data).apps

        #expect(
            apps.map(\.id).sorted() == [6_745_852_921, 6_758_604_043, 6_766_441_698, 6_784_029_039])
    }

    @Test("drops the artist record the API prepends to every artist lookup")
    func dropsArtistRecord() throws {
        let response = try LookupResponse.decode(Fixture.rosterUS.data)

        // The body says 5; four of them are apps.
        #expect(response.reportedCount == 5)
        #expect(response.apps.count == 4)
    }

    @Test("maps every field the roster row needs")
    func mapsFields() throws {
        let apps = try LookupResponse.decode(Fixture.rosterUS.data).apps
        let firstApp = try #require(apps.first { $0.id == 6_745_852_921 })

        #expect(firstApp.name == "BrewSmart: Coffee Ratio")
        #expect(firstApp.bundleID == "com.ken0nek.BrewSmart")
        #expect(firstApp.genre == "Food & Drink")
        #expect(firstApp.formattedPrice == "Free")
        #expect(firstApp.minimumOSVersion == "18.0")
        #expect(firstApp.iconURL.absoluteString.hasSuffix("512x512bb.jpg"))
        #expect(firstApp.storeURL.absoluteString.contains("id6745852921"))
    }

    /// There is no `subtitle` in the response — 44 keys, none of them
    /// the App Store subtitle. A tagline can only ever come from the overlay, so
    /// the decoder must never invent one.
    @Test("leaves the tagline empty because the API has no subtitle to give")
    func hasNoTaglineFromTheAPI() throws {
        let apps = try LookupResponse.decode(Fixture.rosterUS.data).apps

        #expect(apps.allSatisfy { $0.tagline == nil })
    }

    /// `entity=software` omitted. HTTP 200, valid JSON,
    /// `resultCount: 1` — and zero apps. It fails *successfully*, which is how it
    /// survives review and ships as a permanently empty section.
    @Test("yields no apps when entity=software was omitted, and says why")
    func detectsTheMissingEntityParameter() throws {
        let response = try LookupResponse.decode(Fixture.noEntity.data)

        #expect(response.apps.isEmpty)
        // The tell: a non-zero count that contains no software. Callers need to
        // distinguish this from an honestly-empty storefront.
        #expect(response.reportedCount == 1)
        #expect(response.looksLikeMissingEntityParameter)
    }

    /// An app pulled from a storefront is absent, not an error.
    @Test("treats resultCount 0 as a normal empty answer, not a failure")
    func handlesEmptyResult() throws {
        let response = try LookupResponse.decode(Fixture.empty.data)

        #expect(response.apps.isEmpty)
        #expect(response.reportedCount == 0)
        #expect(!response.looksLikeMissingEntityParameter)
    }

    @Test("throws on a body that is not JSON at all")
    func throwsOnMalformedBody() {
        #expect(throws: (any Error).self) {
            try LookupResponse.decode(Fixture.malformed.data)
        }
    }

    @Test("reads the storefront-localized name, not the US one")
    func decodesLocalizedNames() throws {
        let apps = try LookupResponse.decode(Fixture.rosterJP.data).apps
        let secondApp = try #require(apps.first { $0.id == 6_758_604_043 })

        #expect(secondApp.name == "LinkClean – URLクリーナー")
        #expect(secondApp.formattedPrice == "無料")
    }

    /// An artist lookup with `entity=software` returns that
    /// developer's Mac apps alongside their iOS ones, and `wrapperType` is
    /// `software` for both. `kind` is the only thing that separates them, so a
    /// decoder that ignores it hands the resolver rows it cannot reason about.
    @Test("separates Mac apps from iOS apps arriving in one roster")
    func decodesPlatform() throws {
        let apps = try LookupResponse.decode(Fixture.rosterMixedPlatform.data).apps

        #expect(apps.count(where: { $0.platform == .iOS }) == 10)
        #expect(apps.count(where: { $0.platform == .macOS }) == 5)
    }

    /// The Mac rows are not malformed or partial — they carry every field a row
    /// needs, which is exactly why they sail through the decoder and reach the
    /// user as a tappable row.
    @Test("decodes a Mac row completely, macOS version floor and all")
    func decodesMacRowFully() throws {
        let apps = try LookupResponse.decode(Fixture.rosterMixedPlatform.data).apps
        let mac = try #require(apps.first { $0.platform == .macOS })

        #expect(!mac.name.isEmpty)
        #expect(!mac.bundleID.isEmpty)
        // A macOS floor, and one that sorts *below* any shipping iOS version —
        // which is what lets it through a filter that only compares numbers.
        #expect(mac.minimumOSVersion.split(separator: ".").first.flatMap { Int($0) } ?? 99 < 18)
    }

    @Test("decodes the bundleId lookup that starts the discovery chain")
    func decodesBundleIDLookup() throws {
        let apps = try LookupResponse.decode(Fixture.bundleID.data).apps
        let own = try #require(apps.first)

        #expect(own.id == 6_745_852_921)
        #expect(own.artistID == 975_026_926)
    }
}
