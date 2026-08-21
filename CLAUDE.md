# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
swift build
swift test                                                   # hermetic: fixtures, no network
swift test --filter RosterResolverTests                      # one suite
swift test --filter 'RosterResolverTests/excludesHostApp'    # one test
swift format lint --strict --recursive Sources Tests Examples Package.swift   # what CI enforces
swift format --in-place --recursive Sources Tests Examples Package.swift
```

`--filter` matches the **type** name, not the `@Suite("…")` display name the
output prints — and a filter that matches nothing **exits 0**, so read the
"Test run with N tests" line before believing a green run.

`swift build` covers macOS only, so **nothing behind `#if os(iOS)` is compiled by
it or by `swift test`** — the store-sheet presenter and the `AppShowcaseUITests`
assertions included. Run what CI runs before touching `AppShowcaseUI`:

```sh
xcodebuild build-for-testing -scheme AppShowcaseKit-Package \
  -destination 'generic/platform=iOS' -quiet
```

`build-for-testing`, not `build`: plain `build` skips the test targets, so it
misses compile errors in `Tests/AppShowcaseUITests/`.

The example app is outside the package graph, so neither command above compiles
it. Run this before touching `Examples/`:

```sh
xcodebuild build -project Examples/AppShowcaseKitExample.xcodeproj \
  -scheme AppShowcaseKitExampleiOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet
```

The live smoke suite is skipped unless `SHOWCASE_LIVE_BUNDLE_ID` names an app
live on the App Store. It is the only thing that catches a changed wire format,
so run it after touching `LookupEndpoint` or `LookupResponse`:

```sh
SHOWCASE_LIVE_BUNDLE_ID=com.example.YourApp swift test --filter LiveSmoke
```

## Architecture

Two chained calls, nothing configured and nothing hardcoded:

```
Bundle.main.bundleIdentifier → lookup?bundleId=…              → artistId
                             → lookup?id=…&entity=software    → the roster
```

Three products, and the dependency travels one direction only:
`AppShowcaseCore` ← `AppShowcaseStoreKit` ← `AppShowcaseUI`.

- **`AppShowcaseCore`** — every decision worth testing. `LookupEndpoint` (the two
  URL shapes), `LookupResponse` (wire decode + the missing-`entity` diagnostic),
  `RosterResolver` (which rows a given device can show), `ShowcaseLoader`
  (fetch, cache, fall back), `ShowcaseCache`, `StorefrontCode` (alpha-3 → alpha-2).
- **`AppShowcaseStoreKit`** — the only target below the UI allowed to `import
  StoreKit`. The device's storefront, and a never-throwing
  `resolved(overlay:override:)`.
- **`AppShowcaseUI`** — the SwiftUI section, row, and three presenters.

`README.md` carries why each of these exists and which App Store API mistakes they
encode. That reasoning is not repeated here.

## Invariants

Each of these is broken by a change that reads like a simplification.

**`AppShowcaseCore` imports Foundation and nothing else.** That is what lets the
whole chain test without a simulator, so SwiftUI, StoreKit and UIKit all stay
above it — `RunningOS.current` derives the OS from `ProcessInfo` rather than
`UIDevice` for exactly this reason.

**`AppShowcaseUI` inherits every pixel from the host.** It owns no colors, fonts
or strings. The only text it renders arrives from the App Store already
localized. The supported answer to "I want different rows" is `AppShowcaseCore`
plus your own view, not a tint parameter.

**`ShowcaseHostOverride` is host identity, and that is its entire remit.** It
exists because a running bundle identifier and an App Store listing can
disagree — an app extension's identifier is not on the store at all. No tint,
font, string or layout parameter belongs on it or beside it. It reaches
`AppShowcaseSection` through the environment rather than an initializer so the
zero-config call site stays argument-free. Without this paragraph the next reader
adds a cosmetic parameter by analogy.

**The error taxonomy is the cache policy.** `LookupError.transportFailed` is the
only case a stale cache stands in for. `malformedResponse`, `hostAppNotFound`
and `rosterMissingEntityParameter` always throw. Hence `URLSessionTransport`
classifies by HTTP status rather than by whether the bytes parse — a rate limit
and a moved wire format both arrive as unparseable bytes and deserve opposite
answers.

**The cache stores the roster raw, and `RosterResolver` re-runs on every read**,
cache hit included. Filtering depends on the running OS and the caller's overlay,
both of which change without the network changing.

**`RosterResolver` checks platform before version.** A Mac app's floor is a *macOS*
version, which sorts below every shipping iOS version — so a version check applied
across platforms certifies the row it exists to reject.

**No required-reason API.** All three targets ship a `PrivacyInfo.xcprivacy`
declaring none, which rules out `UserDefaults` for the cache (`CA92.1`) and the
file's modification date for freshness (`C617.1`). Freshness comes from a
timestamp written inside the payload.

**iOS is the only supported platform.** macOS, visionOS, tvOS and watchOS are
untested and unclaimed — compiling is not support, so do not add a platform
claim, a badge, or a `platforms:` entry because one of them happens to build.
The `.macOS(.v15)` line in `Package.swift` is a build floor for the test host and
must stay: remove it and SwiftPM falls back to its default deployment target,
where the Foundation-only `AppShowcaseCore` stops compiling, because `Duration`,
`CancellationError` and `URLSession.data(from:delegate:)` all postdate it.

**The Swift floor is 6.2, and one line in `Presenters.swift` is why.** The
store-sheet delegate carries `@MainActor` on the conformance itself — an isolated
conformance (SE-0470), which no compiler before 6.2 can parse at all. Lowering
the floor is not an edit to `Package.swift`: it means rewriting that conformance
as `@preconcurrency`, or as a `nonisolated` method plus `MainActor.assumeIsolated`,
both of which state the isolation less precisely. CI builds `latest-stable`, so
nothing verifies the floor in either direction — it is a claim.

**A team identifier never enters `project.pbxproj`.** Picking a team in Signing &
Capabilities writes one there and dirties the tree with a value nobody else can
use. `Examples/Signing.xcconfig` is the project's base configuration and
optionally includes the git-ignored `Examples/Signing.local.xcconfig` — create
that with `DEVELOPMENT_TEAM = …` to run on hardware. A simulator and CI need
nothing.

**Fixtures are evidence.** `Tests/AppShowcaseCoreTests/Fixtures/` holds unedited
captures from `itunes.apple.com/lookup`, and they are what the behavior above is
argued from. Recapture rather than hand-edit one to make a test pass.
