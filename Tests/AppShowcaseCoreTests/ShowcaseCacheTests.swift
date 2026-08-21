import Foundation
import Testing

@testable import AppShowcaseCore

// MARK: - Doubles

/// Replies from the fixtures and counts how many times it was asked, which is
/// the whole point: a cache that works issues zero requests.
private actor CountingTransport: LookupTransport {
    private(set) var callCount = 0
    private let replies: [Data]

    init(replies: [Data]) { self.replies = replies }

    func data(from _: URL) async throws -> Data {
        defer { callCount += 1 }
        guard callCount < replies.count else { throw LookupError.transportFailed }
        return replies[callCount]
    }

    func calls() -> Int { callCount }
}

private struct FailingTransport: LookupTransport {
    func data(from _: URL) async throws -> Data { throw LookupError.transportFailed }
}

/// 2xx, but the body is not a lookup response — the shape of the wire format
/// moving under us, as opposed to the network being down.
private struct MalformedTransport: LookupTransport {
    func data(from _: URL) async throws -> Data { Data("<html>nope</html>".utf8) }
}

/// In-memory, so the loader suite never touches a filesystem it would have to
/// clean up. `FileShowcaseCache` gets its own tests against a temp directory.
private actor MemoryCache: ShowcaseCache {
    private var storage: [ShowcaseCacheKey: ShowcaseCacheEntry] = [:]
    private(set) var writeCount = 0

    init(seeded: [ShowcaseCacheKey: ShowcaseCacheEntry] = [:]) { storage = seeded }

    func entry(for key: ShowcaseCacheKey) async -> ShowcaseCacheEntry? { storage[key] }

    func store(_ entry: ShowcaseCacheEntry, for key: ShowcaseCacheKey) async {
        storage[key] = entry
        writeCount += 1
    }

    func writes() -> Int { writeCount }
    func stored(_ key: ShowcaseCacheKey) -> ShowcaseCacheEntry? { storage[key] }
}

// MARK: - Fixtures for the cache itself

private let hostBundleID = "com.example.NoteJar"
private let key = ShowcaseCacheKey(
    hostBundleID: hostBundleID, storefront: StorefrontCode(alpha3: "USA")
)
/// A fixed instant, so nothing in this file depends on when it runs.
private let reference = Date(timeIntervalSince1970: 1_800_000_000)

private func app(
    id: Int, platform: ShowcasePlatform = .iOS, minimumOS: String = "18.0"
) -> ShowcaseApp {
    ShowcaseApp(
        id: id,
        artistID: 42,
        name: "App \(id)",
        bundleID: "com.example.app\(id)",
        genre: "Utilities",
        formattedPrice: "Free",
        platform: platform,
        minimumOSVersion: minimumOS,
        iconURL: URL(string: "https://example.com/\(id).png")!,
        storeURL: URL(string: "https://apps.apple.com/app/id\(id)")!
    )
}

private func entry(
    apps: [ShowcaseApp] = [app(id: 1)],
    hostAppID: Int? = 99,
    storedAt: Date = reference
) -> ShowcaseCacheEntry {
    ShowcaseCacheEntry(hostAppID: hostAppID, apps: apps, storedAt: storedAt)
}

// MARK: -

/// The endpoint allows ~20 requests/minute per IP, shared across
/// every app the developer ships on that device. Without a cache a Settings
/// screen re-fetches on every appearance, and a throttled response renders as an
/// empty section.
@Suite("ShowcaseCache")
struct ShowcaseCacheTests {
    // MARK: Key

    @Test("keys a roster by storefront, so a jp capture is never served to a us user")
    func keyIncludesStorefront() {
        let us = ShowcaseCacheKey(hostBundleID: hostBundleID, storefront: .init(alpha3: "USA"))
        let jp = ShowcaseCacheKey(hostBundleID: hostBundleID, storefront: .init(alpha3: "JPN"))

        #expect(us != jp)
        #expect(us.filename != jp.filename)
    }

    /// Nothing enforces bundle-identifier syntax at runtime. A caller passing a
    /// string with a path separator must not be able to write outside the cache
    /// directory.
    @Test(
        "folds anything that could escape the cache directory out of the filename",
        arguments: [
            "../../etc/passwd",
            "com.example/../../evil",
            "com.example.app/../..",
            "/absolute/path",
        ]
    )
    func filenameIsPathSafe(unsafe: String) {
        let filename = ShowcaseCacheKey(
            hostBundleID: unsafe, storefront: .init(alpha3: "USA")
        ).filename

        #expect(!filename.contains("/"))
        #expect(!filename.contains(".."))

        // The property that actually matters: whatever the name looks like,
        // resolving it against a cache directory stays inside that directory.
        let directory = URL(fileURLWithPath: "/tmp/showcase-cache", isDirectory: true)
        let resolved = directory.appendingPathComponent(filename).standardized

        #expect(resolved.deletingLastPathComponent().standardized.path == directory.path)
    }

    /// The digest is not optional any more, so this asserts what the name is
    /// still *for*: a directory you can read by eye. The identifier leads, the
    /// digest follows it.
    @Test("keeps ordinary bundle identifiers readable in the filename")
    func filenameKeepsLegibleIdentifiers() {
        #expect(key.filename == "com.example.NoteJar+1zbw7vmzyigkx.us.json")
    }

    @Test("still produces a usable name when the identifier sanitizes away entirely")
    func filenameSurvivesAnIdentifierOfNothingButSeparators() {
        let filename = ShowcaseCacheKey(
            hostBundleID: "...", storefront: .init(alpha3: "USA")
        ).filename

        #expect(filename.hasPrefix("unknown+"))
        #expect(filename.hasSuffix(".us.json"))
        #expect(!filename.hasPrefix("."), "a leading dot would make it a hidden file")
    }

    /// Sanitizing is lossy and so is the filesystem, and the second one is the
    /// half that is easy to miss. These identifiers must not merely produce
    /// different strings — they must produce different *files* on a volume that
    /// compares case-insensitively, which is every default APFS volume this
    /// package runs on. The initializer invites a shared directory across an app
    /// group, and there a collision means reading another target's roster.
    @Test("gives identifiers that sanitize alike their own files")
    func filenameIsInjectiveAcrossFolding() {
        let identifiers = [
            "com.example.App",
            "com.example.app",
            "com.example_App",
            "com.example/App",
            "com.example App",
            "com.example..App",
        ]

        let filenames = identifiers.map {
            ShowcaseCacheKey(hostBundleID: $0, storefront: .init(alpha3: "USA")).filename
        }

        // Lowercased, because a case-insensitive volume is what decides whether
        // two names are two files. Comparing the strings as written is the
        // assertion that let a case-only collision through.
        #expect(Set(filenames.map { $0.lowercased() }).count == identifiers.count, "\(filenames)")
    }

    /// The logged defect this rewrite exists for. `com.example.App` and
    /// `com.example.app` are two keys and were one file: both survived the old
    /// fast path untouched, and APFS folds their case. Stored under one and read
    /// back under the other, the cache served the wrong roster — and the keys
    /// compare unequal, so `Equatable` never saw it.
    @Test("separates identifiers differing only in case")
    func filenameSeparatesCaseOnlyDifferences() {
        let upper = ShowcaseCacheKey(
            hostBundleID: "com.example.App", storefront: .init(alpha3: "USA")
        ).filename
        let lower = ShowcaseCacheKey(
            hostBundleID: "com.example.app", storefront: .init(alpha3: "USA")
        ).filename

        #expect(upper.lowercased() != lower.lowercased(), "\(upper) vs \(lower)")
    }

    /// The mirror of the test above, and the reason the digest normalizes rather
    /// than hashing the bytes it is handed. These two look like the same kind of
    /// difference as `.App`/`.app` and are its opposite: `Equatable` is
    /// synthesized from `String`, which compares by canonical equivalence, so
    /// this is *one* key. Digesting as-given gave it two files — a miss on an
    /// entry the cache is holding, showing up as two identical-looking names in
    /// a directory whose whole point is being readable by eye.
    @Test("gives identifiers differing only in Unicode normalization one file")
    func filenameJoinsNormalizationOnlyDifferences() {
        let composed = ShowcaseCacheKey(
            hostBundleID: "com.example.Caf\u{00E9}", storefront: .init(alpha3: "USA")
        )
        let decomposed = ShowcaseCacheKey(
            hostBundleID: "com.example.Cafe\u{0301}", storefront: .init(alpha3: "USA")
        )

        #expect(composed == decomposed, "the premise: String calls these one key")
        #expect(
            composed.filename == decomposed.filename,
            "\(composed.filename) vs \(decomposed.filename)"
        )
    }

    /// `NAME_MAX` is 255 bytes, and `sanitize` accepts every script's letters —
    /// so a character-counted bound waved a 300-byte CJK identifier through the
    /// old fast path and every write failed silently. `store` swallows write
    /// failures by design, so the symptom was a cache that never worked rather
    /// than an error anyone could see.
    @Test("keeps the filename inside the byte limit for a non-ASCII identifier")
    func filenameStaysWithinNameMaxForNonASCIIIdentifiers() {
        let filename = ShowcaseCacheKey(
            hostBundleID: String(repeating: "あ", count: 200),
            storefront: .init(alpha3: "USA")
        ).filename

        #expect(filename.utf8.count < 255)
    }

    /// `store` swallows write failures by design, so a name the filesystem
    /// rejects does not surface as an error — the cache just never works.
    @Test("keeps the filename inside the filesystem's limit for any identifier")
    func filenameStaysWithinNameMax() {
        let filename = ShowcaseCacheKey(
            hostBundleID: String(repeating: "com.example.", count: 100),
            storefront: .init(alpha3: "USA")
        ).filename

        #expect(filename.utf8.count < 255)
    }

    /// The digest names a file, so it has to survive relaunch. `Hasher` would
    /// not: it is seeded per process.
    @Test("produces the same filename across separate evaluations")
    func filenameIsStable() {
        let key = ShowcaseCacheKey(
            hostBundleID: "com.example/App", storefront: .init(alpha3: "USA"))

        #expect(
            key.filename
                == ShowcaseCacheKey(
                    hostBundleID: "com.example/App", storefront: .init(alpha3: "USA")
                ).filename)
    }

    // MARK: FileShowcaseCache

    /// Runs the body against a directory that exists only for this test.
    private func withTemporaryCache(
        _ body: (FileShowcaseCache) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppShowcaseKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await body(FileShowcaseCache(directory: directory))
    }

    @Test("round-trips a roster through the filesystem")
    func fileCacheRoundTrips() async throws {
        try await withTemporaryCache { cache in
            let written = entry(apps: [app(id: 1), app(id: 2)])
            await cache.store(written, for: key)

            #expect(await cache.entry(for: key) == written)
        }
    }

    @Test("creates its directory rather than dropping the first write")
    func fileCacheCreatesItsDirectory() async throws {
        try await withTemporaryCache { cache in
            // The directory does not exist until store() makes it.
            await cache.store(entry(), for: key)

            #expect(await cache.entry(for: key) != nil)
        }
    }

    @Test("misses cleanly for a key it has never seen")
    func fileCacheMissesForUnknownKey() async throws {
        try await withTemporaryCache { cache in
            #expect(await cache.entry(for: key) == nil)
        }
    }

    /// A truncated write, or a payload from an older version of the package.
    /// Neither is an error worth propagating — the roster is re-derivable.
    @Test("treats an unreadable payload as a miss rather than throwing")
    func fileCacheTreatsGarbageAsMiss() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppShowcaseKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent(key.filename))

        #expect(await FileShowcaseCache(directory: directory).entry(for: key) == nil)
    }

    /// The timestamp has to survive in the payload, because reading it back off
    /// the file would mean `contentModificationDateKey` — required-reason API
    /// `C617.1`, and a privacy-manifest entry for every consumer.
    @Test("carries its own timestamp in the payload, not in file metadata")
    func timestampLivesInThePayload() async throws {
        try await withTemporaryCache { cache in
            await cache.store(entry(storedAt: reference), for: key)

            let raw = try #require(await cache.entry(for: key))
            #expect(raw.storedAt.timeIntervalSince1970 == reference.timeIntervalSince1970)
        }
    }

    // MARK: Loader integration

    private func loader(
        transport: any LookupTransport,
        cache: (any ShowcaseCache)?,
        os: String = "26.0",
        lifetime: Duration = .seconds(24 * 60 * 60),
        now: @escaping @Sendable () -> Date = { reference }
    ) -> ShowcaseLoader {
        ShowcaseLoader(
            transport: transport,
            hostBundleID: hostBundleID,
            storefront: StorefrontCode(alpha3: "USA"),
            running: .iOS(os),
            overlay: .none,
            cache: cache,
            cacheLifetime: lifetime,
            now: now
        )
    }

    @Test("serves a fresh roster from cache without touching the network")
    func freshCacheSkipsTheNetwork() async throws {
        let transport = CountingTransport(replies: [])
        let cache = MemoryCache(seeded: [key: entry(storedAt: reference)])

        let apps = try await loader(transport: transport, cache: cache).load()

        #expect(await transport.calls() == 0)
        #expect(apps.count == 1)
    }

    @Test("refetches once the entry is older than the lifetime")
    func staleCacheRefetches() async throws {
        let transport = CountingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])
        let day = TimeInterval(24 * 60 * 60)
        let cache = MemoryCache(
            seeded: [key: entry(storedAt: reference.addingTimeInterval(-day - 1))]
        )

        _ = try await loader(transport: transport, cache: cache).load()

        #expect(await transport.calls() == 2)
    }

    @Test("writes what it fetched back to the cache")
    func successfulFetchIsStored() async throws {
        let transport = CountingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])
        let cache = MemoryCache()

        _ = try await loader(transport: transport, cache: cache).load()

        #expect(await cache.writes() == 1)
        let stored = try #require(await cache.stored(key))
        // The *raw* roster, all four apps, host included — resolution is not
        // baked in.
        #expect(stored.apps.count == 4)
        #expect(stored.hostAppID == 6_745_852_921)
        #expect(stored.storedAt == reference)
    }

    /// Yesterday's roster beats a blank section when the network is down.
    @Test("falls back to a stale roster when the transport fails")
    func staleServedOnTransportFailure() async throws {
        let cache = MemoryCache(
            seeded: [key: entry(storedAt: reference.addingTimeInterval(-100 * 24 * 60 * 60))]
        )

        let apps = try await loader(transport: FailingTransport(), cache: cache).load()

        #expect(apps.count == 1)
    }

    @Test("still throws when the transport fails and there is nothing cached")
    func transportFailureWithoutCacheThrows() async {
        await #expect(throws: LookupError.transportFailed) {
            try await loader(transport: FailingTransport(), cache: MemoryCache()).load()
        }
    }

    /// The missing-`entity` diagnostic must not be maskable. A stale roster would make a
    /// missing-`entity` regression look like a working cache, which is exactly
    /// the silent failure this package exists to prevent.
    @Test("never lets a stale roster hide the missing-entity signature")
    func staleDoesNotMaskTheMissingEntityDiagnostic() async throws {
        let transport = CountingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.noEntity.data,
        ])
        let cache = MemoryCache(
            seeded: [key: entry(storedAt: reference.addingTimeInterval(-100 * 24 * 60 * 60))]
        )

        await #expect(throws: LookupError.rosterMissingEntityParameter) {
            try await loader(transport: transport, cache: cache).load()
        }
    }

    /// The distinction the whole fallback rests on. A body that arrived fine and
    /// would not parse means the wire format moved; answering it from cache
    /// would turn a breaking API change into silence lasting until someone
    /// happens to clear their cache.
    @Test("never lets a stale roster hide the wire format changing")
    func staleDoesNotMaskAMalformedResponse() async {
        let cache = MemoryCache(
            seeded: [key: entry(storedAt: reference.addingTimeInterval(-100 * 24 * 60 * 60))]
        )

        await #expect(throws: LookupError.malformedResponse) {
            try await loader(transport: MalformedTransport(), cache: cache).load()
        }
    }

    @Test("never lets a stale roster hide an unlisted host app")
    func staleDoesNotMaskUnlistedHost() async throws {
        let transport = CountingTransport(replies: [try Fixture.empty.data])
        let cache = MemoryCache(
            seeded: [key: entry(storedAt: reference.addingTimeInterval(-100 * 24 * 60 * 60))]
        )

        await #expect(throws: LookupError.hostAppNotFound) {
            try await loader(transport: transport, cache: cache).load()
        }
    }

    /// A timezone change or an NTP correction can put a stored timestamp in the
    /// future. Trusting it would pin the roster until the clock caught up.
    @Test("treats a timestamp from the future as stale, not as fresh forever")
    func clockSkewCountsAsStale() async throws {
        let transport = CountingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])
        let cache = MemoryCache(
            seeded: [key: entry(storedAt: reference.addingTimeInterval(60 * 60 * 24 * 365))]
        )

        _ = try await loader(transport: transport, cache: cache).load()

        #expect(await transport.calls() == 2)
    }

    /// The cache holds the roster as the API gave it, so an OS upgrade takes
    /// effect on the next launch rather than at the next cache expiry.
    @Test("re-applies the OS floor on a cache hit instead of freezing it")
    func resolutionIsReappliedOnEveryHit() async throws {
        let roster = try LookupResponse.decode(try Fixture.rosterUS.data)
        let cache = MemoryCache(
            seeded: [
                key: ShowcaseCacheEntry(
                    hostAppID: 6_745_852_921, apps: roster.apps, storedAt: reference
                )
            ]
        )
        let transport = CountingTransport(replies: [])

        let onOldOS = try await loader(transport: transport, cache: cache, os: "18.0").load()
        let onNewOS = try await loader(transport: transport, cache: cache, os: "26.0").load()

        #expect(await transport.calls() == 0, "both reads came from the same entry")
        #expect(onOldOS.isEmpty)
        #expect(onNewOS.count == 3)
    }

    /// The overlay is a caller-side concern, so it must not be frozen into the
    /// stored payload either.
    @Test("re-applies the overlay on a cache hit")
    func overlayIsReappliedOnEveryHit() async throws {
        let roster = try LookupResponse.decode(try Fixture.rosterUS.data)
        let cache = MemoryCache(
            seeded: [
                key: ShowcaseCacheEntry(
                    hostAppID: 6_745_852_921, apps: roster.apps, storedAt: reference
                )
            ]
        )

        let apps = try await ShowcaseLoader(
            transport: CountingTransport(replies: []),
            hostBundleID: hostBundleID,
            storefront: StorefrontCode(alpha3: "USA"),
            running: .iOS("26.0"),
            overlay: ShowcaseOverlay(excluded: [6_784_029_039]),
            cache: cache,
            cacheLifetime: .seconds(24 * 60 * 60),
            now: { reference }
        ).load()

        #expect(apps.count == 2)
        #expect(!apps.contains { $0.id == 6_784_029_039 })
    }

    @Test("passing no cache fetches every time")
    func nilCacheAlwaysFetches() async throws {
        let transport = CountingTransport(replies: [
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
            try Fixture.bundleID.data, try Fixture.rosterUS.data,
        ])

        _ = try await loader(transport: transport, cache: nil).load()
        _ = try await loader(transport: transport, cache: nil).load()

        #expect(await transport.calls() == 4)
    }
}
