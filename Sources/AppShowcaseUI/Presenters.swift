import AppShowcaseCore
import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// SKStoreProductViewController is API_UNAVAILABLE(visionos), so this block is
// iOS-only rather than "iOS-like". visionOS falls through to StoreLinkPresenter
// along with every other platform without these surfaces. SKOverlay *is*
// available there and would be the better answer the day visionOS is supported
// for real — see the Platforms section of the README.
#if os(iOS)
    import StoreKit

    /// Dismisses the product sheet when the user is finished with it.
    ///
    /// `SKStoreProductViewController` does not dismiss itself: Cancel calls
    /// `productViewControllerDidFinish(_:)`, and the delegate does the work.
    /// With no delegate the button is inert, which on the default tap style
    /// means a sheet the user cannot close.
    ///
    /// One shared instance, and that is the load-bearing part.
    /// `SKStoreProductViewController.delegate` is `weak`, and
    /// ``StoreSheetPresenter`` is a struct built fresh at each tap and dropped
    /// as soon as `present` returns — so a delegate it owned would deallocate
    /// before the user could reach Cancel, leaving the button exactly as dead
    /// but the code looking fixed. The delegate has to outlive the tap, and
    /// nothing here holds state worth scoping to one.
    ///
    /// `@MainActor` appears twice, and both are load-bearing. On the type,
    /// because the callback dismisses a view controller and that is main-actor
    /// work. On the conformance, because the StoreKit protocol carries no
    /// isolation of its own, and satisfying it from an isolated type is a data
    /// race Swift 6 rejects outright. Drop the first and it still compiles, with
    /// a warning, and still works — StoreKit calls back on the main thread —
    /// which is what makes the omission easy to keep.
    ///
    /// The second one is an *isolated conformance* (SE-0470), and it is why
    /// `Package.swift` declares a 6.2 tools version: no earlier compiler can
    /// parse this line. Rewriting it for an older toolchain is possible —
    /// `@preconcurrency`, or a `nonisolated` method plus
    /// `MainActor.assumeIsolated` — but both state the isolation less precisely
    /// than the annotation does, which is why the floor moved instead.
    @MainActor
    final class StoreSheetDismisser: NSObject, @MainActor SKStoreProductViewControllerDelegate {
        static let shared = StoreSheetDismisser()

        func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
            // Asks the presenter to dismiss rather than dismissing the
            // controller directly, so a sheet presented from an already-presented
            // controller unwinds to the right place.
            viewController.presentingViewController?.dismiss(animated: true)
        }
    }

    /// Presents the full App Store product page as a sheet — screenshots,
    /// description, Get button — without leaving the host app.
    ///
    /// The most convincing of the three, and the heaviest.
    @MainActor
    public struct StoreSheetPresenter: ShowcasePresenter {
        public init() {}

        public func present(_ app: ShowcaseApp, attribution: ShowcaseAttribution) {
            guard let host = UIWindow.topViewController else {
                // Nothing to present from. Falling back keeps the tap working
                // rather than silently doing nothing.
                StoreLinkPresenter().present(app, attribution: attribution)
                return
            }

            var parameters: [String: Any] = [
                SKStoreProductParameterITunesItemIdentifier: NSNumber(value: app.id)
            ]
            if let token = attribution.providerToken {
                parameters[SKStoreProductParameterProviderToken] = token
            }
            if let campaign = attribution.campaignToken {
                parameters[SKStoreProductParameterCampaignToken] = campaign
            }

            let controller = SKStoreProductViewController()
            controller.delegate = StoreSheetDismisser.shared
            host.present(controller, animated: true)
            // Loading after presenting shows Apple's own spinner rather than a
            // dead tap while the page fetches.
            controller.loadProduct(withParameters: parameters) { _, _ in }
        }
    }

    /// Presents a compact App Store card that slides up from the bottom edge.
    ///
    /// The lightest interruption available: no screenshots, no description, and
    /// the user can install without the Settings screen going away.
    @MainActor
    public struct OverlayPresenter: ShowcasePresenter {
        public init() {}

        public func present(_ app: ShowcaseApp, attribution: ShowcaseAttribution) {
            guard let scene = UIWindow.activeScene else {
                StoreLinkPresenter().present(app, attribution: attribution)
                return
            }

            let configuration = SKOverlay.AppConfiguration(
                appIdentifier: String(app.id), position: .bottom)
            if let token = attribution.providerToken {
                configuration.providerToken = token
            }
            if let campaign = attribution.campaignToken {
                configuration.campaignToken = campaign
            }

            SKOverlay(configuration: configuration).present(in: scene)
        }
    }
#endif

/// Opens `apps.apple.com` in the App Store app.
///
/// No StoreKit dependency and it works everywhere — but it backgrounds the host,
/// which is the worst outcome for a tap that started in Settings. It is also the
/// fallback the other two use when there is no scene to present from.
@MainActor
public struct StoreLinkPresenter: ShowcasePresenter {
    public init() {}

    public func present(_ app: ShowcaseApp, attribution: ShowcaseAttribution) {
        let url = attribution.decorating(app.storeURL)
        // UIKit first: Mac Catalyst satisfies both `canImport` checks and wants
        // UIKit. The `#else` is the durable half — this presenter is what the
        // other two fall back to when there is no scene, so a platform where it
        // silently does nothing is a platform where every tap in the kit
        // silently does nothing. A platform matching no arm fails to build
        // rather than falling through to an empty body.
        #if canImport(UIKit) && !os(watchOS)
            UIApplication.shared.open(url)
        #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
        #else
            #error("StoreLinkPresenter has no way to open a URL on this platform")
        #endif
    }
}

#if canImport(UIKit) && !os(watchOS)
    extension UIWindow {
        static var activeScene: UIWindowScene? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        }

        /// Walks past presented sheets so the store page does not try to present
        /// from a controller that is already covered.
        static var topViewController: UIViewController? {
            var top = activeScene?.keyWindow?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
#endif
