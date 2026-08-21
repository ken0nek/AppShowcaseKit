import Foundation

/// The OS the host app is running on: which one, and which version.
///
/// The two travel together because neither decides anything alone. A version
/// string cannot say what it is a version *of*, and "12.0" is a macOS release
/// that predates iOS 13 while also being an iOS release from 2018. Comparing a
/// store listing's floor against the wrong number line is how a Mac app ends up
/// looking installable on an iPhone, so this type exists to make that comparison
/// impossible to write by accident.
public struct RunningOS: Sendable, Equatable, Hashable {
    public let platform: ShowcasePlatform
    /// Dotted and major-first, e.g. `"18.4.1"`.
    public let version: String

    public init(platform: ShowcasePlatform, version: String) {
        self.platform = platform
        self.version = version
    }

    /// This device, right now.
    ///
    /// Derived entirely from Foundation and the compile-time platform, which is
    /// what keeps `AppShowcaseCore` free of UIKit — `UIDevice.systemVersion` is
    /// the obvious source and would cost the whole target its Foundation-only
    /// guarantee, and with it the ability to test all of this without a simulator.
    public static var current: RunningOS {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return RunningOS(
            platform: compiledPlatform,
            version:
                "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }

    /// visionOS falls in with iOS deliberately: a visionOS device installs from
    /// the iOS App Store, and the lookup API has no separate `kind` for it —
    /// `software` and `mac-software` are the only two it returns.
    private static var compiledPlatform: ShowcasePlatform {
        #if os(macOS)
            .macOS
        #else
            .iOS
        #endif
    }
}
