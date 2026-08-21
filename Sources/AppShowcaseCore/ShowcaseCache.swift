import Foundation

/// Identifies one cached roster.
///
/// The storefront is part of the identity, not decoration. A roster is
/// storefront-localized, so serving a `jp` capture to a `us` user reproduces
/// the wrong-storefront bug exactly — Japanese names, yen prices — except now it arrives from
/// disk instead of from a malformed query string, which is harder to spot.
public struct ShowcaseCacheKey: Sendable, Equatable, Hashable {
    public let hostBundleID: String
    public let storefront: StorefrontCode

    public init(hostBundleID: String, storefront: StorefrontCode) {
        self.hostBundleID = hostBundleID
        self.storefront = storefront
    }

    /// A filesystem-safe filename for this key.
    ///
    /// Bundle identifiers are conventionally alphanumerics, dots and hyphens,
    /// but nothing enforces that at runtime — a caller can hand us any string,
    /// and one containing `/` would write outside the cache directory.
    /// Everything outside the safe set is folded to `_`.
    ///
    /// Dots survive, because they are most of what a bundle identifier is, but
    /// runs of them are collapsed: dropping the separators out of `../..` would
    /// otherwise leave `..` sitting inside the name. Harmless here — the result
    /// always carries a suffix, so it can never *be* a relative component — but
    /// a filename that reads as a traversal attempt is a trap for whoever
    /// touches this next.
    ///
    /// **Every name carries a digest of the original identifier, with no
    /// exception for well-formed ones.** The stem alone cannot identify a key:
    /// sanitizing is lossy, so `com.example/App` and `com.example_App` fold
    /// together — and the filesystem is lossy too, which is the half that is
    /// easy to miss. APFS compares case-insensitively, so `com.example.App` and
    /// `com.example.app` are one file however distinct the two strings are. In
    /// a directory shared across an app group that means reading another
    /// target's roster. The digest separates every pair the stem and the
    /// filesystem between them merge.
    ///
    /// **The identifier is normalized to NFC first, and case is deliberately
    /// left alone.** The two look like the same kind of difference and are
    /// opposites here, because `String` is what decides whether two keys are
    /// one. Swift compares by canonical equivalence, so `é` as one scalar and
    /// as `e` + combining acute are a single key that must reach a single file
    /// — digesting the bytes as given would split it, and the miss would land
    /// on an entry that is present. Case is the reverse: `.App` and `.app` are
    /// two keys by the same rule, and it is only the filesystem that merges
    /// them, so folding case here would recreate the collision this digest
    /// exists to prevent.
    ///
    /// The stem is still there, so a cache directory stays readable by eye —
    /// `com.example.NoteJar+1zbw7vmzyigkx.us.json` says what it holds. NFC
    /// leaves every ASCII identifier untouched, so this costs real ones nothing.
    public var filename: String {
        // Normalized before both halves, not just the digest: matching stems
        // would otherwise rely on the filesystem folding the leftover
        // difference, which is exactly the kind of assumption the digest is
        // here to stop making.
        let identifier = hostBundleID.precomposedStringWithCanonicalMapping
        return "\(Self.sanitize(identifier))+\(Self.digest(identifier))"
            + ".\(storefront.parameterValue).json"
    }

    /// Leaves room for the digest, the storefront and the extension inside the
    /// 255-**byte** limit every filesystem here imposes. Bytes, not characters:
    /// `sanitize` accepts `Character.isLetter`, which is true for every script,
    /// so a 100-character CJK identifier is 300 bytes and a character count
    /// would wave it through. Without a bound in the right unit, a long enough
    /// identifier makes every write fail — and `store` is deliberately silent
    /// about failures, so the cache would never work.
    ///
    /// The rest of the budget: one `+`, at most 13 digits of digest
    /// (`UInt64.max` in radix 36 is `3w5e11264sgsf`), a dot, two storefront
    /// characters and `.json` — 22 bytes.
    private static let maximumStemBytes = 180

    private static func sanitize(_ identifier: String) -> String {
        var safe = ""
        var bytes = 0
        for character in identifier {
            let isSafe =
                character.isLetter || character.isNumber || character == "." || character == "-"
            let next = isSafe ? character : "_"
            if next == ".", safe.last == "." { continue }
            // Measured before appending, so the budget is never overshot and a
            // multi-byte character is never cut in half.
            let width = String(next).utf8.count
            if bytes + width > maximumStemBytes { break }
            safe.append(next)
            bytes += width
        }
        // A trailing dot would meet the extension's own dot and rebuild `..`
        // across the join. A leading one would make a hidden file.
        while safe.first == "." { safe.removeFirst() }
        while safe.last == "." { safe.removeLast() }
        // An identifier made entirely of separators sanitizes away to nothing.
        return safe.isEmpty ? "unknown" : safe
    }

    /// FNV-1a. Chosen over `Hasher` because that one is seeded per process, so
    /// its output would name a different file on every launch and the cache
    /// would never hit.
    private static func digest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }
}

/// A roster as the API returned it, plus when it arrived.
public struct ShowcaseCacheEntry: Codable, Sendable, Equatable {
    /// The host's own App Store ID. Cached because self-exclusion
    /// needs it, and it comes from the *first* of the two calls — a cache that
    /// stored only the roster would list the host inside itself on every hit.
    public let hostAppID: Int?

    /// The roster *before* resolution. Filtering and ordering depend on the
    /// running OS and the caller's overlay, both of which change without the
    /// network changing, so they are re-applied on every read rather than
    /// frozen in here.
    public let apps: [ShowcaseApp]

    /// Written into the payload, and deliberately never read back off the
    /// filesystem.
    ///
    /// The obvious implementation asks the file for its modification date —
    /// and `NSURL.contentModificationDateKey` and its siblings are
    /// required-reason API `C617.1`, so that one line would land in every
    /// consumer's privacy manifest. Same shape as the `UserDefaults` question:
    /// the storage you reach
    /// for first is the one that files paperwork for you.
    public let storedAt: Date

    public init(hostAppID: Int?, apps: [ShowcaseApp], storedAt: Date) {
        self.hostAppID = hostAppID
        self.apps = apps
        self.storedAt = storedAt
    }
}

/// Where a fetched roster lives between launches.
///
/// The lookup endpoint allows roughly 20 requests per minute per IP,
/// shared across every app you ship on that device. A Settings screen that
/// fetches on each appearance will hit that ceiling on a device carrying a few
/// of your apps, and the endpoint's answer to a throttled caller is an error
/// body — which this package renders as an empty section. The cache is what
/// keeps the section populated.
///
/// Non-throwing on purpose: to a caller, a cache that fails and a cache that
/// misses are the same event — go to the network. A cache must never surface an
/// error.
public protocol ShowcaseCache: Sendable {
    func entry(for key: ShowcaseCacheKey) async -> ShowcaseCacheEntry?
    func store(_ entry: ShowcaseCacheEntry, for key: ShowcaseCacheKey) async
}

/// The default cache: one JSON file per storefront under `Caches/`.
///
/// `Caches` rather than `Application Support` because a roster is re-derivable
/// from the network at any time. That makes it correct for the system to evict
/// under pressure, and correct for it to stay out of the user's backups and
/// iCloud quota — which `Caches` gives us without setting a resource value.
public struct FileShowcaseCache: ShowcaseCache {
    private let directory: URL?

    /// - Parameter directory: Defaults to `Caches/AppShowcaseKit`. Pass one
    ///   explicitly to share a cache across an app group, or to point tests at
    ///   a temporary directory.
    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    private static var defaultDirectory: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("AppShowcaseKit", isDirectory: true)
    }

    public func entry(for key: ShowcaseCacheKey) async -> ShowcaseCacheEntry? {
        guard let url = directory?.appendingPathComponent(key.filename),
            let data = try? Data(contentsOf: url)
        else { return nil }

        // A truncated or older-format payload is a miss, never a throw. The
        // roster is always re-derivable, so there is nothing here worth
        // propagating to a caller.
        return try? Self.decoder.decode(ShowcaseCacheEntry.self, from: data)
    }

    public func store(_ entry: ShowcaseCacheEntry, for key: ShowcaseCacheKey) async {
        guard let directory,
            let data = try? Self.encoder.encode(entry)
        else { return }

        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // Atomic, so a crash mid-write leaves yesterday's roster intact instead
        // of a half-file that decodes to nothing.
        try? data.write(to: directory.appendingPathComponent(key.filename), options: .atomic)
    }

    /// ISO-8601 rather than the `Date` default of seconds-since-2001, so a
    /// cache file can be read by a human debugging why a roster looks stale.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Duration {
    /// `Date` arithmetic speaks `TimeInterval`. The public API speaks
    /// `Duration`, because `.seconds(24 * 60 * 60)` says what `86_400` does not.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
