import Foundation
import Testing

@testable import AppShowcaseCore

@Suite("RunningOS")
struct RunningOSTests {
    /// The whole point of pairing the two: a bare version string cannot say
    /// which OS it belongs to, and "12.0" means opposite things depending.
    @Test("reports the platform the host was compiled for")
    func reportsCompiledPlatform() {
        #if os(macOS)
            #expect(RunningOS.current.platform == .macOS)
        #else
            #expect(RunningOS.current.platform == .iOS)
        #endif
    }

    /// A dotted, major-first string, because ``RosterResolver`` splits it on `.`
    /// and compares component-wise against a store's `minimumOsVersion`.
    @Test("reports a version shaped so it can be compared against a store floor")
    func reportsAComparableVersion() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

        #expect(RunningOS.current.version.hasPrefix("\(major)."))
    }
}
