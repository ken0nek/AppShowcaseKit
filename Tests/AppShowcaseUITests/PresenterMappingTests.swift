import AppShowcaseCore
import Testing

@testable import AppShowcaseUI

/// The mapping from a tap style to a presenter is the one place in this module
/// where a platform fork decides whether code exists at all, and a fork that is
/// wrong does not misbehave — it fails to compile, on a platform nobody built.
/// These run on whatever platform the suite is compiled for, so the assertions
/// are written per-platform rather than assuming iOS.
@Suite("Presenter mapping")
struct PresenterMappingTests {
    /// Exhaustive over `CaseIterable` rather than over three literals: a fourth
    /// tap style added without a presenter arm must fail here, not at the
    /// first tap on whichever platform was not built.
    @MainActor
    @Test("resolves a presenter for every tap style")
    func everyStyleResolvesToAPresenter() {
        for style in ShowcaseTapStyle.allCases {
            _ = style.makePresenter()
        }

        #expect(ShowcaseTapStyle.allCases.count == 3)
    }

    /// `StoreLinkPresenter` is the universal fallback — the other two presenters
    /// call it when there is no scene, so a platform where it is missing is a
    /// platform where every tap in the kit does nothing. It carries no platform
    /// guard for exactly that reason, and this asserts the guard stays off.
    @MainActor
    @Test("resolves the store link on every platform")
    func storeLinkResolvesEverywhere() {
        #expect(ShowcaseTapStyle.storeLink.makePresenter() is StoreLinkPresenter)
    }

    /// The in-app surfaces are iOS-only. Everywhere else both of them fall back
    /// to leaving the app, which is worse but is not nothing — and "not nothing"
    /// is the property worth pinning down.
    @MainActor
    @Test("maps the in-app styles to in-app presenters only where they exist")
    func mapsInAppStylesPerPlatform() {
        let sheet = ShowcaseTapStyle.storeSheet.makePresenter()
        let overlay = ShowcaseTapStyle.overlay.makePresenter()

        #if os(iOS)
            #expect(sheet is StoreSheetPresenter)
            #expect(overlay is OverlayPresenter)
        #else
            #expect(sheet is StoreLinkPresenter)
            #expect(overlay is StoreLinkPresenter)
        #endif
    }

    /// The default is what an adopter gets by writing nothing, so it is the arm
    /// most worth naming: if `.storeSheet` ever stops resolving, it stops
    /// resolving for everyone who took the default.
    @MainActor
    @Test("resolves the default tap style")
    func defaultStyleResolves() {
        #expect(ShowcaseTapStyle.default == .storeSheet)

        #if os(iOS)
            #expect(ShowcaseTapStyle.default.makePresenter() is StoreSheetPresenter)
        #else
            #expect(ShowcaseTapStyle.default.makePresenter() is StoreLinkPresenter)
        #endif
    }
}
