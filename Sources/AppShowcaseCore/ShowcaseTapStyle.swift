/// How a tapped row opens the App Store.
///
/// Lives in Core rather than UI so a host that draws its own rows can still
/// declare the behavior without importing StoreKit. `AppShowcaseUI` maps each
/// case to a presenter.
///
/// All three ship because the choice is genuinely reversible — it is one value at
/// one call site, with no persisted state and no wire shape behind it.
public enum ShowcaseTapStyle: String, Sendable, Equatable, CaseIterable, Codable {
    /// `SKStoreProductViewController` — the full product page as a sheet:
    /// screenshots, description, Get button. The most convincing option, and the
    /// user never leaves your app.
    case storeSheet

    /// `SKOverlay` — a compact App Store card that slides up from the bottom. No
    /// screenshots and no description, but the lightest possible interruption.
    /// Needs a `UIWindowScene`.
    case overlay

    /// A plain link to `apps.apple.com`. No StoreKit dependency and it works
    /// anywhere — but it backgrounds your app, which is the worst outcome for a
    /// tap that started in Settings.
    case storeLink

    public static let `default` = ShowcaseTapStyle.storeSheet

    /// Whether choosing this style sends the user out of the host app.
    public var leavesApp: Bool { self == .storeLink }
}
