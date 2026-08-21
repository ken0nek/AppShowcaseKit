/// Optional curation applied on top of live discovery.
///
/// The point of the whole design is that this is *optional*. Pass ``none`` and the
/// kit is pure discovery: the roster maintains itself, and shipping a new app
/// makes it appear everywhere with no code change. Fill some of it in and you get
/// curation without ever hand-maintaining the roster.
///
/// Keep it small. A roster you have to edit is the failure mode this package
/// exists to avoid.
public struct ShowcaseOverlay: Sendable, Equatable {
    /// App Store ID → the one line of copy the API has no field for.
    /// Localize by building this from the host's own string catalog — the kit
    /// deliberately owns no strings.
    public var taglines: [Int: String]

    /// App Store IDs to show first, in this order. **Not an allowlist** — apps
    /// not named here still appear, after these, in the order the API returned
    /// them. That way shipping app #5 needs no edit here.
    public var order: [Int]

    /// App Store IDs to hide — a retired app, or one that makes no sense next to
    /// this particular host.
    public var excluded: Set<Int>

    public init(taglines: [Int: String] = [:], order: [Int] = [], excluded: Set<Int> = []) {
        self.taglines = taglines
        self.order = order
        self.excluded = excluded
    }

    /// Pure live discovery. The default, and the one that needs no maintenance.
    public static let none = ShowcaseOverlay()
}
