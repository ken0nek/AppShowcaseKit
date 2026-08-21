import AppShowcaseCore
import Foundation

extension ShowcaseLoader {
    /// The apps this device can install, or empty.
    ///
    /// Everything the loader needs, read from the environment: the host's own
    /// bundle identifier and the device's storefront. Silent by design — a
    /// Settings screen never reports that a cross-promotion failed to load — so
    /// a caller can gate a row on `isEmpty` without handling an error.
    ///
    /// Cancellation resolves to empty along with everything else. ``load()``
    /// propagates it deliberately. This method promises never to throw, and its
    /// caller is a task that is going away regardless.
    /// - Parameter override: Host identity, for the cases where the running
    ///   bundle is not the one on the App Store — see ``ShowcaseHostOverride``.
    ///   Each `nil` field falls back to the environment, so naming an identifier
    ///   does not commit the caller to naming a storefront too.
    public static func resolved(
        overlay: ShowcaseOverlay = .none,
        override: ShowcaseHostOverride = .none
    ) async -> [ShowcaseApp] {
        let host = effectiveHost(
            override: override,
            environmentBundleID: Bundle.main.bundleIdentifier,
            environmentStorefront: await StorefrontCode.current
        )
        return await resolved(
            transport: URLSessionTransport(),
            hostBundleID: host.bundleID,
            storefront: host.storefront,
            overlay: overlay,
            cache: FileShowcaseCache()
        )
    }

    /// Which identity actually reaches the endpoint.
    ///
    /// Separate from ``resolved(overlay:override:)`` because that one reads the
    /// real bundle and the real storefront and builds a real `URLSession` — so
    /// the precedence rule cannot be proven through it. This is the whole rule,
    /// and it is the part worth pinning: a `nil` field means *fall back to the
    /// environment*, never *use an empty value*.
    ///
    /// The environment storefront arrives already resolved rather than being
    /// read here, because `StorefrontCode.current` is `nil` on a host with no
    /// App Store account and populated on a signed-in one — untestable by
    /// decision, and the reason this function takes it as a parameter.
    static func effectiveHost(
        override: ShowcaseHostOverride,
        environmentBundleID: String?,
        environmentStorefront: StorefrontCode
    ) -> (bundleID: String, storefront: StorefrontCode) {
        // An empty override is absent, not a value — a host that binds the field
        // to a text field writes one the moment the user clears it, and
        // `bundleId=` is a lookup whose only possible answer is
        // `hostAppNotFound`.
        let overriddenBundleID = override.bundleID.flatMap { $0.isEmpty ? nil : $0 }
        return (
            bundleID: overriddenBundleID ?? environmentBundleID ?? "",
            storefront: override.storefront ?? environmentStorefront
        )
    }

    /// Environment seam. Callers have no reason to inject any of this, but the
    /// silence contract cannot be proven against the real network or the real
    /// bundle, and it is the whole point of the method above.
    static func resolved(
        transport: any LookupTransport,
        hostBundleID: String,
        storefront: StorefrontCode,
        overlay: ShowcaseOverlay,
        cache: (any ShowcaseCache)?
    ) async -> [ShowcaseApp] {
        (try? await ShowcaseLoader(
            transport: transport,
            hostBundleID: hostBundleID,
            storefront: storefront,
            overlay: overlay,
            cache: cache
        ).load()) ?? []
    }
}
