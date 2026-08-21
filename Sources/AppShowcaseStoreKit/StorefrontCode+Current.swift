import AppShowcaseCore

#if canImport(StoreKit)
    import StoreKit
#endif

extension StorefrontCode {
    /// The device's current App Store storefront.
    ///
    /// StoreKit reports alpha-3 and the lookup API takes alpha-2.
    /// ``StorefrontCode/init(alpha3:)`` converts. Falls back to the US
    /// storefront when StoreKit has no answer — offline on first launch, mostly.
    public static var current: StorefrontCode {
        get async {
            #if canImport(StoreKit)
                return StorefrontCode(alpha3: await Storefront.current?.countryCode ?? "USA")
            #else
                return StorefrontCode(alpha3: "USA")
            #endif
        }
    }
}
