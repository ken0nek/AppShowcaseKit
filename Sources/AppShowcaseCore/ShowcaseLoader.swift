import Foundation

/// What can go wrong fetching a roster. Each case is actionable: none of them
/// ever reaches a user, and all of them reach a developer.
public enum LookupError: Error, Equatable, Sendable {
    /// The network call failed, or the endpoint answered with a non-2xx status.
    ///
    /// Transient by assumption, which is why this is the *only* error a cached
    /// roster is allowed to stand in for. A throttled caller lands here
    /// too — the endpoint answers 403 — and that is precisely the case the cache
    /// exists to survive.
    case transportFailed

    /// The endpoint answered 2xx with a body that is not a lookup response.
    ///
    /// Deliberately distinct from ``transportFailed``: this is the signature of
    /// the wire format moving under us, and a stale cache must never stand in
    /// for it. Serving yesterday's roster here would turn a breaking API change
    /// into silence that lasts until someone happens to clear their cache.
    case malformedResponse

    /// The host app is not on the App Store in this storefront — TestFlight-only,
    /// unreleased, or delisted. There is no `artistId` to chain from.
    case hostAppNotFound

    /// The roster call came back with results but no apps, which is
    /// the exact signature of a request missing `entity=software`. Reported
    /// rather than swallowed: an empty roster and a malformed request look
    /// identical from the call site, and only one of them is a bug.
    case rosterMissingEntityParameter
}

/// Fetches bytes for a URL. The only I/O in Core, behind a protocol so the whole
/// chain tests against captured fixtures.
///
/// An implementation must throw ``LookupError/transportFailed`` for a non-2xx
/// status as well as for a connection failure. The distinction between that and
/// a 2xx body that will not decode is load-bearing — see
/// ``LookupError/malformedResponse``.
public protocol LookupTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

/// `URLSession`-backed transport. The default for real callers.
public struct URLSessionTransport: LookupTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            // A throttled or erroring endpoint still hands back a body, and that
            // body is not JSON. Classifying it by status here is what keeps it
            // from being mistaken for the wire format changing.
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LookupError.transportFailed
            }
            return data
        } catch is CancellationError {
            // Cancellation is not a network failure. Swallowing it would let a
            // superseded or torn-down load resolve anyway, defeating the
            // structured-concurrency contract the caller is relying on.
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LookupError.transportFailed
        }
    }
}

/// Resolves the showcase roster from the host's own bundle identifier.
///
/// Nothing is configured and nothing is hardcoded: the host's bundle ID yields
/// its `artistId`, which yields every app that developer publishes. Ship a new
/// app and it appears in the others with no code change anywhere.
public struct ShowcaseLoader: Sendable {
    private let transport: any LookupTransport
    private let hostBundleID: String
    private let storefront: StorefrontCode
    private let running: RunningOS
    private let overlay: ShowcaseOverlay
    private let cache: (any ShowcaseCache)?
    private let cacheLifetime: Duration
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - cache: Where the roster is kept between launches. On by default:
    ///     the rate limit is one you hit by *not* caching, so making the fix
    ///     opt-in would leave it armed for anyone who skims. Pass `nil`
    ///     to fetch every time.
    ///   - cacheLifetime: How long a stored roster counts as fresh. A day, by
    ///     default — a roster only changes when you ship or pull an app.
    public init(
        transport: any LookupTransport = URLSessionTransport(),
        hostBundleID: String,
        storefront: StorefrontCode,
        running: RunningOS = .current,
        overlay: ShowcaseOverlay = .none,
        cache: (any ShowcaseCache)? = FileShowcaseCache(),
        cacheLifetime: Duration = .seconds(24 * 60 * 60)
    ) {
        self.init(
            transport: transport,
            hostBundleID: hostBundleID,
            storefront: storefront,
            running: running,
            overlay: overlay,
            cache: cache,
            cacheLifetime: cacheLifetime,
            now: Date.init
        )
    }

    /// Clock seam. Internal because callers have no reason to move time, but
    /// the freshness and clock-skew tests need to.
    init(
        transport: any LookupTransport = URLSessionTransport(),
        hostBundleID: String,
        storefront: StorefrontCode,
        running: RunningOS = .current,
        overlay: ShowcaseOverlay = .none,
        cache: (any ShowcaseCache)?,
        cacheLifetime: Duration,
        now: @escaping @Sendable () -> Date
    ) {
        self.transport = transport
        self.hostBundleID = hostBundleID
        self.storefront = storefront
        self.running = running
        self.overlay = overlay
        self.cache = cache
        self.cacheLifetime = cacheLifetime
        self.now = now
    }

    /// The two-call discovery chain, resolved and filtered.
    ///
    /// An empty result is a legitimate answer — every sibling filtered out by OS
    /// floor, or a developer with one app — and is not an error.
    ///
    /// A fresh cache entry short-circuits both calls. A stale one is still
    /// preferred over a network failure: yesterday's roster is a roster, and
    /// blanking a Settings section because a train went into a tunnel is worse
    /// than showing one app that has since been pulled.
    public func load() async throws -> [ShowcaseApp] {
        let key = ShowcaseCacheKey(hostBundleID: hostBundleID, storefront: storefront)
        let cached = await cache?.entry(for: key)

        if let cached, isFresh(cached) { return resolve(cached) }

        do {
            let fetched = try await fetchRoster()
            await cache?.store(fetched, for: key)
            return resolve(fetched)
        } catch LookupError.transportFailed {
            // Only a transport failure falls back, and every other case is
            // deliberately excluded: `rosterMissingEntityParameter` is a bug
            // signal that has to reach a developer, `malformedResponse`
            // means the wire format moved, and `hostAppNotFound` is a stable
            // fact about the store rather than a blip. A stale roster papering
            // over any of those would buy silence at the price of the diagnostic.
            guard let cached else { throw LookupError.transportFailed }
            return resolve(cached)
        }
    }

    private func fetchRoster() async throws -> ShowcaseCacheEntry {
        let identity = try await fetch(.identity(bundleID: hostBundleID, storefront: storefront))
        guard let host = identity.apps.first else { throw LookupError.hostAppNotFound }

        let roster = try await fetch(.roster(artistID: host.artistID, storefront: storefront))
        if roster.looksLikeMissingEntityParameter {
            throw LookupError.rosterMissingEntityParameter
        }

        return ShowcaseCacheEntry(hostAppID: host.id, apps: roster.apps, storedAt: now())
    }

    /// Resolution runs on every load, cache hit included, because it depends on
    /// the running OS and the caller's overlay — both of which change without
    /// the network changing. An OS upgrade takes effect on the next launch, not
    /// on the next cache expiry.
    private func resolve(_ entry: ShowcaseCacheEntry) -> [ShowcaseApp] {
        RosterResolver(
            hostAppID: entry.hostAppID,
            running: running,
            overlay: overlay
        ).resolve(entry.apps)
    }

    private func isFresh(_ entry: ShowcaseCacheEntry) -> Bool {
        let age = now().timeIntervalSince(entry.storedAt)
        // A negative age means the clock moved backwards — a timezone change, an
        // NTP correction, or a user setting the date forward and back. Treating
        // that as fresh would pin a roster until the clock caught up, so a
        // timestamp from the future counts as stale.
        return age >= 0 && age < cacheLifetime.timeInterval
    }

    private func fetch(_ endpoint: LookupEndpoint) async throws -> LookupResponse {
        let data = try await transport.data(from: endpoint.url)
        do {
            return try LookupResponse.decode(data)
        } catch {
            // Not `transportFailed`: the bytes arrived with a 2xx and did not
            // parse, which means the wire format moved. See `malformedResponse`.
            throw LookupError.malformedResponse
        }
    }
}
