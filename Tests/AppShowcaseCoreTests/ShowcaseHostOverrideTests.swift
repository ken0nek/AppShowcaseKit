import Testing

@testable import AppShowcaseCore

/// The override exists so a host whose running bundle identifier is not the one
/// on the App Store can still resolve — an extension, a Catalyst variant. Both
/// fields are optional because `nil` means "read the environment", and a caller
/// overriding one must not be forced to invent the other.
@Suite("Showcase host override")
struct ShowcaseHostOverrideTests {
    /// Every caller that has never heard of this type gets this value, so a
    /// default carrying anything would silently redirect them at another
    /// developer's roster.
    @Test("defaults to overriding nothing")
    func noneOverridesNothing() {
        #expect(ShowcaseHostOverride.none.bundleID == nil)
        #expect(ShowcaseHostOverride.none.storefront == nil)
    }

    /// A partial override is the common case, not an edge one: naming an
    /// identifier while keeping the device's real storefront is what an
    /// extension wants.
    @Test("carries one field without requiring the other")
    func partialOverrideLeavesTheOtherNil() {
        let override = ShowcaseHostOverride(bundleID: "com.apple.Pages")

        #expect(override.bundleID == "com.apple.Pages")
        #expect(override.storefront == nil)
    }

    /// It travels through SwiftUI's environment, which compares values to decide
    /// what to invalidate. An override that never compared equal would redraw
    /// the section on every environment change.
    @Test("compares by value")
    func equatableHolds() {
        #expect(ShowcaseHostOverride(bundleID: "a") == ShowcaseHostOverride(bundleID: "a"))
        #expect(ShowcaseHostOverride(bundleID: "a") != ShowcaseHostOverride(bundleID: "b"))
        #expect(
            ShowcaseHostOverride(bundleID: "a", storefront: .init(alpha3: "USA"))
                != ShowcaseHostOverride(bundleID: "a", storefront: .init(alpha3: "JPN"))
        )
    }
}
