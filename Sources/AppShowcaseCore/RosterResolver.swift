/// Turns a raw lookup roster into the rows a given host app actually shows.
///
/// Pure and synchronous: no network, no clock, no storage. Everything that makes
/// the roster *wrong* rather than *stale* is decided here, which is why this is
/// the piece with the most tests.
public struct RosterResolver: Sendable {
    private let hostAppID: Int?
    private let running: RunningOS
    private let runningVersion: [Int]
    private let overlay: ShowcaseOverlay

    /// - Parameters:
    ///   - hostAppID: The `trackId` of the app doing the showing. Pass `nil` only
    ///     when the host is not on the App Store — every shipped caller has one,
    ///     and omitting it makes the app list itself.
    ///   - running: The OS this app is running on. ``RunningOS/current`` unless a
    ///     test is moving it.
    ///   - overlay: Optional curation. The default is pure live discovery.
    public init(
        hostAppID: Int?,
        running: RunningOS,
        overlay: ShowcaseOverlay = .none
    ) {
        self.hostAppID = hostAppID
        self.running = running
        self.overlay = overlay
        runningVersion = Self.components(running.version)
    }

    public func resolve(_ apps: [ShowcaseApp]) -> [ShowcaseApp] {
        let kept =
            apps
            .filter { $0.id != hostAppID && !overlay.excluded.contains($0.id) && canInstall($0) }
            .map { app in
                var app = app
                app.tagline = overlay.taglines[app.id]
                return app
            }
        return Self.pin(kept, toFrontIn: overlay.order)
    }

    /// Pinned apps lead, in the order given. Everything else keeps the order the
    /// API returned. A pin naming an app that is not in the roster is ignored, so
    /// a stale list degrades to "no opinion" rather than to an empty section. An
    /// id named twice degrades the same way, and for the same reason: the list is
    /// a statement about order, and the earliest mention is the only reading of a
    /// repeat that keeps that statement true, so later mentions are dropped.
    private static func pin(_ apps: [ShowcaseApp], toFrontIn order: [Int]) -> [ShowcaseApp] {
        guard !order.isEmpty else { return apps }
        let rank = Dictionary(
            order.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return apps.enumerated()
            .sorted { lhs, rhs in
                switch (rank[lhs.element.id], rank[rhs.element.id]) {
                case (let left?, let right?): left < right
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Whether this device can install this app: the right store first, then
    /// the OS floor within it.
    ///
    /// Both halves earn their place. Any developer whose apps do not all share
    /// one deployment target has rows that some of their own users cannot
    /// install, and any developer who ships to both stores has rows that *no*
    /// user of the other one can.
    ///
    /// The order matters. Platform is checked first because the version check is
    /// meaningless — actively misleading — across two number lines: a Mac app's
    /// "needs 12.0" sits below every shipping iOS version, so on an iPhone the
    /// floor test does not merely fail to catch it, it certifies it. Only once
    /// both sides are known to be the same OS does comparing their versions mean
    /// anything.
    private func canInstall(_ app: ShowcaseApp) -> Bool {
        app.platform == running.platform
            && !Self.isLower(runningVersion, than: Self.components(app.minimumOSVersion))
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// Numeric, component-wise. A string compare would rank "9.0" above "18.0"
    /// and happily offer an iOS 9 device an app requiring iOS 26.
    private static func isLower(_ lhs: [Int], than rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
