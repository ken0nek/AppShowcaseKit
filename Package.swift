// swift-tools-version: 6.2
import PackageDescription

// 6.2 is a compiler floor, not a manifest-format preference. `Presenters.swift`
// spells its delegate conformance `@MainActor SKStoreProductViewControllerDelegate`
// — an isolated conformance (SE-0470), which no compiler before 6.2 can parse. A
// lower floor is accepted by toolchains that then fail mid-build, on a line that
// reads like ordinary syntax. This one turns that into a resolve-time error
// naming the version it wants. Lowering it means rewriting that conformance
// — `@preconcurrency`, or a `nonisolated` method plus `MainActor.assumeIsolated`
// — not just this number. Nothing here verifies the floor: CI builds with
// `latest-stable` Xcode, so 6.2 is a claim, not a tested fact.
let package = Package(
    name: "AppShowcaseKit",
    // iOS is the supported platform, and the only one this package claims.
    //
    // The iOS floor is policy rather than constraint: Core is Foundation-only and
    // UI's newest API is iOS 15, so both would compile far lower — but a floor is
    // a promise to keep working, and this one is set where the package is
    // actually built and run. Raising a floor later breaks adopters. Lowering one
    // never does, so if you need iOS 15, open an issue rather than a fork.
    //
    // The macOS floor is NOT a support claim, and it is not removable. `swift
    // build` and `swift test` run on a Mac host, and that is the entire hermetic
    // suite. Delete the line and SwiftPM falls back to its default deployment
    // target, where `Duration`, `CancellationError` and
    // `URLSession.data(from:delegate:)` do not exist yet — and every resulting
    // error is inside the Foundation-only Core. macOS is where the tests run, not
    // something the package speaks for. README's Platforms section is the claim.
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // The package. All of the hard-won behavior lives here, and it is
        // Foundation-only, so the tests run without a simulator.
        .library(name: "AppShowcaseCore", targets: ["AppShowcaseCore"]),
        // The device's storefront and a silent, cache-first resolve, so an app
        // can gate a row on the roster count. Separate product because it is
        // what makes Core's Foundation-only charter affordable: the StoreKit
        // dependency stops here rather than reaching down.
        .library(name: "AppShowcaseStoreKit", targets: ["AppShowcaseStoreKit"]),
        // Optional convenience. Separate product so importing Core never drags
        // in StoreKit. Ships ZERO configuration — see README.
        .library(name: "AppShowcaseUI", targets: ["AppShowcaseUI"]),
    ],
    targets: [
        // All three targets ship a privacy manifest declaring no collection, no
        // tracking and no required-reason API use. Copied rather than processed
        // so the filename survives verbatim — Apple's tooling looks for exactly
        // `PrivacyInfo.xcprivacy`.
        .target(
            name: "AppShowcaseCore",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        // The only target below the UI layer allowed to import StoreKit. Core
        // depends on nothing and this depends on Core, so the dependency has
        // one direction to travel and cannot reach the Foundation-only module.
        .target(
            name: "AppShowcaseStoreKit",
            dependencies: ["AppShowcaseCore"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        // Core is listed even though it arrives transitively through
        // AppShowcaseStoreKit: this module imports Core's types directly, and an
        // explicit dependency says so.
        .target(
            name: "AppShowcaseUI",
            dependencies: ["AppShowcaseCore", "AppShowcaseStoreKit"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "AppShowcaseCoreTests",
            dependencies: ["AppShowcaseCore"],
            resources: [.process("Fixtures")]
        ),
        // Core is listed even though it arrives transitively: the tests build a
        // stub conforming to Core's `LookupTransport`, so they import it
        // directly, and an explicit dependency says so.
        .testTarget(
            name: "AppShowcaseStoreKitTests",
            dependencies: ["AppShowcaseStoreKit", "AppShowcaseCore"]
        ),
        // The UI target's platform forks are the part of this package a macOS
        // `swift build` cannot speak for: a presenter that does not exist on a
        // platform is a compile error, and nothing else here would surface it.
        // Core is listed even though it arrives transitively, because these
        // tests name `ShowcaseTapStyle`, which Core owns.
        .testTarget(
            name: "AppShowcaseUITests",
            dependencies: ["AppShowcaseUI", "AppShowcaseCore"]
        ),
    ]
)
