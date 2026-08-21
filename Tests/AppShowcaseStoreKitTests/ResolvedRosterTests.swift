import AppShowcaseCore
import Foundation
import Testing

@testable import AppShowcaseStoreKit

private struct FailingTransport: LookupTransport {
    func data(from url: URL) async throws -> Data { throw LookupError.transportFailed }
}

@Suite("resolved")
struct ResolvedRosterTests {
    @Test("answers empty instead of throwing when the lookup fails")
    func silentOnFailure() async {
        let apps = await ShowcaseLoader.resolved(
            transport: FailingTransport(),
            hostBundleID: "com.example.NoteJar",
            storefront: StorefrontCode(alpha3: "USA"),
            overlay: .none,
            cache: nil
        )
        #expect(apps.isEmpty)
    }

    /// The point of the override: an extension's own identifier is not on the
    /// App Store, so the identifier that reaches the endpoint has to be the one
    /// the host named rather than the one it is running under.
    @Test("prefers an overridden bundle identifier over the running bundle")
    func overrideBundleIDBeatsTheRunningBundle() {
        let host = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(bundleID: "com.apple.Pages"),
            environmentBundleID: "com.example.AppShowcaseKitExampleiOS",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.bundleID == "com.apple.Pages")
    }

    @Test("prefers an overridden storefront over the device's own")
    func overrideStorefrontBeatsTheDeviceStorefront() {
        let host = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(storefront: StorefrontCode(alpha3: "JPN")),
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.storefront.parameterValue == "jp")
    }

    /// A `nil` field means *read the environment*, not *use an empty value*.
    /// Overriding only the identifier is the common case, and a storefront
    /// silently reset to a default would serve a US roster to a Japanese user —
    /// the wrong-storefront bug, arriving through the fix for a different one.
    @Test("falls back to the environment for whichever field is not overridden")
    func unsetFieldsFallBackToTheEnvironment() {
        let partial = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(bundleID: "com.apple.Pages"),
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "JPN")
        )

        #expect(partial.bundleID == "com.apple.Pages")
        #expect(partial.storefront.parameterValue == "jp", "the storefront was not overridden")

        let neither = ShowcaseLoader.effectiveHost(
            override: .none,
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(neither.bundleID == "com.example.NoteJar")
        #expect(neither.storefront.parameterValue == "us")
    }

    /// The same absence, arriving as an empty string rather than as `nil` —
    /// what a host binding the field to a text field writes the moment the user
    /// clears it. `bundleId=` is a lookup whose only possible answer is
    /// `hostAppNotFound`, so a cleared field reads as *use the running bundle*.
    @Test("treats an emptied override as absent rather than as a value")
    func emptyOverrideFallsBackToTheEnvironment() {
        let host = ShowcaseLoader.effectiveHost(
            override: ShowcaseHostOverride(bundleID: ""),
            environmentBundleID: "com.example.NoteJar",
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.bundleID == "com.example.NoteJar")
    }

    /// A host with no bundle identifier at all — the `?? ""` arm. It resolves to
    /// `hostAppNotFound` rather than crashing, which is the behavior that
    /// existed before the override and must survive it.
    @Test("survives a host with no bundle identifier")
    func missingEnvironmentIdentifierIsEmptyRatherThanFatal() {
        let host = ShowcaseLoader.effectiveHost(
            override: .none,
            environmentBundleID: nil,
            environmentStorefront: StorefrontCode(alpha3: "USA")
        )

        #expect(host.bundleID.isEmpty)
    }
}
