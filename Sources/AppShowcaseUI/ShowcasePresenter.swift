import AppShowcaseCore

/// Opens an app's App Store page.
///
/// A seam, deliberately: which of the three is right depends on how much
/// interruption a given app's Settings screen can afford, and that is a taste
/// call best made against a real screen. Swapping is one value at one call site —
/// no persisted state, no wire shape, nothing to migrate.
@MainActor
public protocol ShowcasePresenter: Sendable {
    func present(_ app: ShowcaseApp, attribution: ShowcaseAttribution)
}

extension ShowcaseTapStyle {
    /// The presenter for this style.
    ///
    /// On platforms without StoreKit's in-app surfaces, both in-app styles fall
    /// back to opening the store URL — the tap still works, it just leaves.
    @MainActor
    public func makePresenter() -> any ShowcasePresenter {
        #if os(iOS)
            switch self {
            case .storeSheet: StoreSheetPresenter()
            case .overlay: OverlayPresenter()
            case .storeLink: StoreLinkPresenter()
            }
        #else
            StoreLinkPresenter()
        #endif
    }
}
