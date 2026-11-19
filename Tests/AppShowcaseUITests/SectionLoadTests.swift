import AppShowcaseCore
import AppShowcaseStoreKit
import Testing

@testable import AppShowcaseUI

@Suite("Section load")
struct SectionLoadTests {
    @Test("records nothing for a cancelled load, even one that came back with a roster")
    func cancelledLoadDoesNotLand() {
        #expect(ShowcaseSectionLoad.landed(.roster([]), isCancelled: true) == nil)
    }

    @Test("records nothing for a load that did not finish")
    func unfinishedLoadDoesNotLand() {
        #expect(ShowcaseSectionLoad.landed(.unfinished, isCancelled: false) == nil)
    }

    @Test("records an empty roster as an answer")
    func emptyRosterLands() {
        #expect(ShowcaseSectionLoad.landed(.roster([]), isCancelled: false) == [])
    }
}
