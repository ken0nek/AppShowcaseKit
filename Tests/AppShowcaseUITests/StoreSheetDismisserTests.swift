#if os(iOS)
    import StoreKit
    import Testing

    @testable import AppShowcaseUI

    /// `SKStoreProductViewController.delegate` is `weak` and the presenter that
    /// sets it is a struct discarded at the end of the tap. Whether the delegate
    /// survives that is the difference between a Cancel button that works and
    /// one that looks wired up and is not, so it is the property worth pinning.
    @Suite("Store sheet dismisser")
    struct StoreSheetDismisserTests {
        /// One instance, reused. A fresh instance per tap would be released as
        /// soon as the presenter went away, which is the bug this guards.
        @MainActor
        @Test("hands back the same instance every time")
        func sharedInstanceIsStable() {
            #expect(StoreSheetDismisser.shared === StoreSheetDismisser.shared)
        }

        /// The delegate property is `weak`: assigning an object nothing else
        /// holds leaves it nil. This asserts the assignment actually sticks,
        /// which is the whole reason `shared` exists rather than an inline
        /// instance.
        @MainActor
        @Test("survives assignment to a weak delegate property")
        func assignmentSurvivesTheWeakProperty() {
            let controller = SKStoreProductViewController()

            controller.delegate = StoreSheetDismisser.shared

            #expect(controller.delegate === StoreSheetDismisser.shared)
        }
    }
#endif
