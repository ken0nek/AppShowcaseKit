# AppShowcaseKit

[![CI](https://github.com/ken0nek/AppShowcaseKit/actions/workflows/ci.yml/badge.svg)](https://github.com/ken0nek/AppShowcaseKit/actions/workflows/ci.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](#platforms)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Shows your other App Store apps in a Settings screen. Takes no configuration.

```swift
import AppShowcaseUI

Form {
    // …your settings…

    AppShowcaseSection {
        Text("More from me")
    }
}
```

That is the whole integration. No app IDs, no plist, no roster to maintain.

## Install

```swift
.package(url: "https://github.com/ken0nek/AppShowcaseKit.git", from: "1.0.0")
```

Then depend on `AppShowcaseUI` (rows included), `AppShowcaseStoreKit` (the
roster count, so you can decide whether to show a row at all), or
`AppShowcaseCore` (draw your own).

The package is consumed as source, so "breaking" here means a change to a public
type, to an initializer's defaults, or to the shape of what
`ShowcaseLoader.load()` returns. Those wait for a major version, which is what
makes plain `from:` the right pin.

If your host's running bundle identifier is not the one on the App Store — an
app extension has its own, and it is not listed at all — name the one that is:

```swift
.environment(\.showcaseHostOverride, .init(bundleID: "com.example.YourApp"))
```

The default path needs none of this, which is why it arrives through the
environment rather than as an argument you have to skip past.

## How it finds your apps

```
Bundle.main.bundleIdentifier            com.example.NoteJar
  → lookup?bundleId=…                   artistId 1234567890
  → lookup?id=…&entity=software         every app you publish
```

Nothing is hardcoded, so **shipping a new app makes it appear in all the others
with no code change**. Names, icons, genres and prices arrive already localized to
the user's storefront.

## Why this is a package and not forty lines of SwiftUI

Because those forty lines have ten ways to be quietly wrong. Each is encoded and
tested here:

| Mistake | What it does to you |
|---|---|
| Artist lookup without `entity=software` | HTTP 200, valid JSON, `resultCount: 1`, **zero apps**. Fails *successfully*, so it ships and the section is empty forever |
| `Storefront.current.countryCode` is alpha-3 | `country=JPN` silently serves the **US** storefront — wrong language, price, and ratings |
| Ignoring `kind` | `entity=software` returns your **Mac** apps too, and `wrapperType` is `software` for both. A Mac app's floor is a *macOS* version, which sorts below every shipping iOS version, so the OS-floor check below does not just miss it — it certifies it |
| No `minimumOsVersion` filter | Rows that dead-end on a device that cannot install them |
| Caching in `UserDefaults` | Drags required-reason API `CA92.1` into your privacy manifest |
| No caching | ~20 requests/min per IP, shared across all your apps on that device |
| Expecting a `subtitle` | There is none. 44 keys, and the App Store subtitle is not among them |
| Forgetting self-exclusion | Your app lists itself |
| Icons with no store affordance | Search API terms require the icon sit proximate to a store badge |
| Treating a missing app as an error | An app pulled from one storefront is absent — that is a normal answer |

## Three products

**`AppShowcaseCore`** — Foundation only. The resolver, the storefront table, the
cache. No SwiftUI, no StoreKit, no dependencies. Tests run without a simulator.

**`AppShowcaseStoreKit`** — the device's storefront (`StorefrontCode.current`)
and a cache-first resolve that answers with an empty roster rather than throwing
(`ShowcaseLoader.resolved(overlay:override:)`). Use it to gate a row on the
roster count, because a Settings row that opens an empty screen is worse than no
row at all.

```swift
import AppShowcaseCore
import AppShowcaseStoreKit

let apps = await ShowcaseLoader.resolved()
if !apps.isEmpty { /* show your "More from me" row */ }
```

Both imports, because this module does not re-export `AppShowcaseCore` — which
module owns a symbol stays visible at the call site.

**`AppShowcaseUI`** — optional. Rows, and the three presenters. It ships **zero
cosmetic configuration** on purpose: no colors, no fonts, no copy. The only text
it renders comes from the App Store, already localized. If you want rows that
match your design system, use `AppShowcaseCore` and draw your own — that is the
supported path, not a workaround.

## Choosing how a tap opens the store

```swift
AppShowcaseSection(tapStyle: .overlay) { Text("More from me") }
```

| `ShowcaseTapStyle` | Leaves your app? | Shows |
|---|---|---|
| `.storeSheet` *(default)* | No | Full product page as a sheet — screenshots, description, Get |
| `.overlay` | No | Compact `SKOverlay` card from the bottom edge |
| `.storeLink` | **Yes** | Opens the App Store app |

Both in-app presenters fall back to the store link when there is no scene, so a
tap never silently does nothing.

## Caching

On by default — the rate limit is one you hit by *not* caching. One JSON file per
storefront under `Caches/`, with a one-day lifetime:

```swift
ShowcaseLoader(
    hostBundleID: …, storefront: …,
    cache: FileShowcaseCache(),          // or nil to fetch every time
    cacheLifetime: .seconds(24 * 60 * 60)
)
```

Three details that are not obvious:

- **A stale roster beats an empty section.** If the network fails and a cached
  roster exists — however old — it is served.
- **Stale never masks a bug.** The fallback covers transport failures only.
  `malformedResponse`, `hostAppNotFound` and `rosterMissingEntityParameter`
  always throw, because answering those from cache would turn a breaking API
  change into silence.
- **Filtering is re-applied on every read, not frozen in.** The cache stores the
  roster as the API gave it, so an OS upgrade or a changed overlay takes effect
  on the next launch rather than at the next cache expiry.

`ShowcaseCache` is a two-method protocol if you would rather store it yourself.

## Measuring it

```swift
AppShowcaseSection(
    attribution: .init(providerToken: "1234567", hostBundleID: Bundle.main.bundleIdentifier!)
) { Text("More from me") }
```

The provider token is the one value the kit cannot derive — it belongs to your App
Store Connect account. The campaign token defaults to `showcase-<your app>`, so
App Analytics attributes the install to the app that showed the row. Without a
provider token everything still works, unmeasured.

To measure the *tap* rather than the install, there is a callback:

```swift
AppShowcaseSection(onSelect: { app in
    analytics.capture(.showcaseAppTapped(appID: app.id, name: app.name))
}) { Text("More from me") }
```

It fires **before** the store is presented, because `.storeLink` backgrounds the
app and a capture racing that transition is a capture you lose. The kit names no
event and defines no taxonomy.

## Curating, if you want to

```swift
AppShowcaseSection(
    overlay: .init(
        taglines: [1234567890: String(localized: "showcase.notejar.tagline")],
        order: [1234567890],
        excluded: [9876543210]
    )
) { Text("More from me") }
```

All three fields are optional. `order` is **not** an allowlist — apps it does not
mention still appear, after the pinned ones, so a pin list written today does not
hide the app you ship next year.

Taglines are the only route to a subtitle. Build the dictionary from your own
string catalog. The kit deliberately owns no strings.

## Behavior worth knowing

- **Never shows an error.** A Settings screen does not tell users a
  cross-promotion failed to load. Failures leave the section empty.
- **Empty means invisible.** No rows, no header, no gap.
- **Shows only what this device can install.** The right store first, then the OS
  floor within it. An iOS host never lists your Mac apps, a Mac host never lists
  your iOS ones, and neither lists an app the running OS is too old for.
- **No fallback to another storefront.** If your apps are not sold where the user
  is, the section is empty. Retrying in `us` would produce rows that dead-end at
  a store page the user cannot buy from.
- **No star ratings.** Rating counts are per-storefront and thin enough that
  showing them reads as broken in half the world.

## Privacy

All three targets ship a `PrivacyInfo.xcprivacy` declaring no collection, no
tracking, and **no required-reason API use**. Keeping the last one true is why
the roster is cached to a file rather than to `UserDefaults` (`CA92.1`), and why
freshness comes from a timestamp inside the payload rather than from the file's
modification date (`C617.1`).

The only request the package makes carries your app's own bundle identifier and a
storefront code, to Apple's public lookup endpoint. Nothing else leaves the
device, and what it writes to disk is public App Store metadata.

## Platforms

**Swift 6.2** · **iOS 18**. iOS is the supported platform and the only one this
package claims. **macOS, visionOS, tvOS and watchOS are not supported** — no UI
here is exercised anywhere but iOS. Several of them compile, and compiling is not
the bar. `RunningOS` folds every non-Mac platform into `.iOS`, so a visionOS
device would compare *its* version numbers against *iOS* floors.

`Package.swift` carries a macOS floor, and it is **not** a support claim: `swift
build` and `swift test` run on a Mac host, and without it the Foundation-only
core does not compile at all.

The Swift floor is a compiler floor. The store-sheet delegate is satisfied by an
isolated conformance (SE-0470), which no compiler before 6.2 can parse, so
declaring it makes an older toolchain fail at resolve rather than mid-build. The
iOS floor is policy — both targets would compile considerably lower. If you need
either floor moved, or another platform supported, open an issue.

## Testing

```sh
swift test                                                 # hermetic; fixtures, no network
SHOWCASE_LIVE_BUNDLE_ID=com.example.YourApp swift test --filter LiveSmoke
swift format --in-place --recursive Sources Tests Examples Package.swift
```

Fixtures under `Tests/AppShowcaseCoreTests/Fixtures/` are **unedited captures**
from `itunes.apple.com/lookup`. They are the evidence base for the mistakes above,
so recapture them rather than hand-editing to suit a test.

The live smoke suite catches what frozen fixtures cannot — a changed response
shape, a dropped field, a new rate limit. It is skipped unless that variable is
set, and works against any bundle identifier live on the App Store. The
localization check additionally needs that app sold in both the US and Japanese
storefronts, and says so if it is not.

## Example app

`Examples/AppShowcaseKitExample.xcodeproj` builds an iOS host with two tabs.
**Inspector** drives the throwing `ShowcaseLoader.load()` and names what came
back, so `hostAppNotFound` and `rosterMissingEntityParameter` are legible instead
of silent. Type any App Store identifier, switch storefront, switch tap style,
toggle the cache. **Zero-config** is `AppShowcaseSection` in the shape an adopter
would write it, taking its tap style from the Inspector.

Run it on a device to see a tap actually open the store. A simulator has no App
Store, so the store presenters have nothing to present there — the section
renders, and every tap goes nowhere.

A device build needs a team identifier, and this project stores none: create
`Examples/Signing.local.xcconfig` with `DEVELOPMENT_TEAM = ABCDE12345` and Xcode
picks it up through `Examples/Signing.xcconfig`. The file is git-ignored. The
simulator needs nothing.

## License

MIT. See [LICENSE](LICENSE).
