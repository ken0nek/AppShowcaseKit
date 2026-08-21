#if os(iOS)
    import SwiftUI
    import Testing

    import AppShowcaseCore

    @testable import AppShowcaseUI

    /// The environment is how the override reaches ``AppShowcaseSection`` without
    /// appearing in its initializer. That indirection is the point — and it is
    /// also what makes the default worth asserting, because every adopter
    /// inherits it without ever naming it.
    @Suite("Host override environment")
    struct HostOverrideEnvironmentTests {
        /// A default carrying an identifier would silently point every
        /// zero-config host at another developer's roster, and nothing at the
        /// call site would hint at it.
        @MainActor
        @Test("defaults to overriding nothing")
        func defaultsToNone() {
            #expect(EnvironmentValues().showcaseHostOverride == .none)
        }

        @MainActor
        @Test("carries a value that was set")
        func carriesAnAssignedOverride() {
            var values = EnvironmentValues()

            values.showcaseHostOverride = .init(bundleID: "com.apple.Pages")

            #expect(values.showcaseHostOverride.bundleID == "com.apple.Pages")
            #expect(values.showcaseHostOverride.storefront == nil, "one field, not both")
        }
    }
#endif
