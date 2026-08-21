/// Which store an app is sold in.
///
/// An artist lookup with `entity=software` returns that developer's
/// **Mac apps alongside their iOS ones**, and `wrapperType` is `software` for
/// both. Only `kind` separates them, so a roster built without reading it hands
/// iPhone users rows for apps that exist solely on the Mac App Store.
///
/// The OS-floor filter cannot catch those on its own, and in fact waves them
/// through: a Mac app's `minimumOsVersion` is a *macOS* version, and macOS
/// version numbers are numerically lower than any shipping iOS version. "Needs
/// macOS 12.0" reads to a version comparison as comfortably below iOS 18, so the
/// row survives the one filter that exists to prevent exactly this. Two OS
/// number lines are not comparable, and the only safe move is to never compare
/// across them.
///
/// Mac rows routinely make up a fifth of a mixed catalog's roster, and they
/// arrive fully populated — every field a row needs — so nothing about them
/// looks wrong on the way through.
public enum ShowcasePlatform: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// `kind: "software"`. The iOS App Store, which is also what a visionOS
    /// device installs from.
    case iOS

    /// `kind: "mac-software"`. The Mac App Store.
    case macOS

    /// Maps the response's `kind` field.
    ///
    /// Returns `nil` for anything unrecognized, which drops the row. That is the
    /// deliberate direction to fail in: a row we cannot classify is a row we
    /// cannot say the device can install, and this package would rather show one
    /// app less than one dead end. If Apple ever renames these, a whole roster
    /// drops and ``LookupResponse/looksLikeMissingEntityParameter`` fires — the
    /// diagnosis will read "missing entity parameter" rather than "the wire moved",
    /// but a developer gets an error rather than a silently empty section.
    init?(kind: String?) {
        switch kind {
        case "software": self = .iOS
        case "mac-software": self = .macOS
        default: return nil
        }
    }
}
