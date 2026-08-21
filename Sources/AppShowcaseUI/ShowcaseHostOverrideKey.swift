import AppShowcaseCore
import SwiftUI

extension EnvironmentValues {
    /// Host identity for a view tree whose running bundle is not the one on the
    /// App Store — an app extension, a Catalyst variant, a diagnostic harness.
    ///
    /// Delivered through the environment rather than as an initializer
    /// parameter, and that is the load-bearing part. ``AppShowcaseSection``
    /// takes no arguments, which is the whole product: a host that needs none of
    /// this must not meet a configuration knob in autocomplete to discover
    /// that it does not. Set here, the override is invisible to everyone who
    /// never looks for it.
    ///
    /// ```swift
    /// Form {
    ///     AppShowcaseSection { Text("More from me") }
    /// }
    /// .environment(\.showcaseHostOverride, .init(bundleID: "com.example.App"))
    /// ```
    ///
    /// The default is ``ShowcaseHostOverride/none``, and it has to be: every
    /// adopter inherits this value without asking for it, so a default carrying
    /// an identifier would point every zero-config host at someone else's
    /// roster.
    @Entry public var showcaseHostOverride: ShowcaseHostOverride = .none
}
