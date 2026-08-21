import Testing

@testable import AppShowcaseCore

/// `Storefront.current.countryCode` hands back ISO 3166-1 **alpha-3**
/// ("JPN"); the lookup API's `country` parameter wants **alpha-2** ("jp"). Pass
/// the alpha-3 through and the API does not complain — it quietly serves the US
/// storefront, so every name, price and rating is wrong in a way nothing surfaces.
@Suite("StorefrontCode")
struct StorefrontCodeTests {
    @Test("converts the alpha-3 StoreKit hands you into the alpha-2 the API wants")
    func convertsAlpha3ToAlpha2() {
        #expect(StorefrontCode(alpha3: "JPN").parameterValue == "jp")
    }

    @Test(
        "covers the storefronts that carry the bulk of App Store revenue",
        arguments: [
            ("USA", "us"), ("GBR", "gb"), ("DEU", "de"), ("FRA", "fr"),
            ("CAN", "ca"), ("AUS", "au"), ("CHN", "cn"), ("KOR", "kr"),
            ("TWN", "tw"), ("ESP", "es"), ("ITA", "it"), ("BRA", "br"),
            ("MEX", "mx"), ("IND", "in"), ("NLD", "nl"), ("SWE", "se"),
            ("CHE", "ch"), ("SGP", "sg"), ("HKG", "hk"), ("POL", "pl"),
        ]
    )
    func convertsMajorStorefronts(alpha3: String, expected: String) {
        #expect(StorefrontCode(alpha3: alpha3).parameterValue == expected)
    }

    /// The table is the whole point of the type. A trimmed table degrades
    /// silently to US for everyone it dropped, so guard its size.
    @Test("carries the full ISO region table, not a handful of favorites")
    func tableIsComplete() {
        #expect(StorefrontCode.knownAlpha3Count >= 200)
    }

    /// Apple ships storefronts this table will not have on the day they open.
    /// Falling back to `us` gives a real page in a real language; propagating
    /// the alpha-3 gives a silently wrong storefront.
    @Test("falls back to us for a code it does not know")
    func fallsBackForUnknownCode() {
        #expect(StorefrontCode(alpha3: "ZZZ").parameterValue == "us")
    }

    @Test("accepts the lowercase a caller might hand it")
    func isCaseInsensitive() {
        #expect(StorefrontCode(alpha3: "jpn").parameterValue == "jp")
    }
}
