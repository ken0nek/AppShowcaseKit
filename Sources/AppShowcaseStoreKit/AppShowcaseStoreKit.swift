// AppShowcaseStoreKit — the device's storefront, read in one place.
//
// This is the module where StoreKit is allowed. AppShowcaseCore stays
// Foundation-only, and tests without a simulator and without a network, because
// this module absorbs the dependency on its behalf.
//
// It exists so an adopter never re-derives the device's storefront. That read
// hands back an ISO 3166-1 alpha-3 code and the lookup API takes alpha-2 — the
// failure mode `StorefrontCode` documents, silent because the wrong code serves
// the US storefront rather than an error — so every app that writes the line by
// hand is one more place for it to be written wrong.
//
// The same reasoning covers the resolve: an app that wants to know whether it
// has anything to show asks one question. It does not assemble a loader and
// then decide what to do with errors a Settings screen must never report.
