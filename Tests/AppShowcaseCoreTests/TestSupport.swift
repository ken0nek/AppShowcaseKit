@testable import AppShowcaseCore

extension RunningOS {
    /// An iOS device at `version`. Most tests are about the version and take the
    /// platform for granted; the ones that are about the platform say so by
    /// reaching for ``macOS(_:)`` instead.
    static func iOS(_ version: String) -> RunningOS {
        RunningOS(platform: .iOS, version: version)
    }

    static func macOS(_ version: String) -> RunningOS {
        RunningOS(platform: .macOS, version: version)
    }
}
