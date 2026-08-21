import Foundation

/// Campaign tokens, so App Analytics can tell you which of your apps sent the
/// install.
///
/// This is the one value the kit cannot derive from the device: the provider
/// token belongs to your App Store Connect account, not to the app. Without it,
/// everything still works — you just cannot tell whether it worked.
public struct ShowcaseAttribution: Sendable, Equatable {
    /// Your App Analytics provider token. Same value for every app on one
    /// account.
    public var providerToken: String?

    /// Names the source of the install. Defaults to `showcase-<host app>`, so
    /// App Analytics attributes the install to the app that showed the row with
    /// nothing configured per app.
    public var campaignToken: String?

    public init(providerToken: String? = nil, campaignToken: String? = nil) {
        self.providerToken = providerToken
        self.campaignToken = campaignToken
    }

    /// Derives the campaign token from the host's bundle identifier — the last
    /// component, lowercased. `com.example.NoteJar` → `showcase-notejar`.
    public init(providerToken: String?, hostBundleID: String) {
        self.providerToken = providerToken
        let slug = hostBundleID.split(separator: ".").last.map { $0.lowercased() } ?? "unknown"
        campaignToken = "showcase-\(slug)"
    }

    /// No attribution. Every presenter still works. Nothing is measured.
    public static let none = ShowcaseAttribution()

    /// Appends `pt`, `ct` and `mt` to a store URL, preserving whatever query the
    /// API already put there (`trackViewUrl` arrives carrying `uo=4`).
    ///
    /// Returns the URL untouched when there is no provider token: App Analytics
    /// ignores a campaign token that arrives without one, so emitting it alone
    /// would only look like attribution was working.
    public func decorating(_ storeURL: URL) -> URL {
        guard let providerToken,
            var components = URLComponents(url: storeURL, resolvingAgainstBaseURL: false)
        else { return storeURL }

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "pt", value: providerToken))
        if let campaignToken {
            items.append(URLQueryItem(name: "ct", value: campaignToken))
        }
        items.append(URLQueryItem(name: "mt", value: "8"))
        components.queryItems = items

        return components.url ?? storeURL
    }
}
