import Foundation

/// Typed-address presets for device checks of the automatic map origin (`HomeOriginPolicy`). Each preset is a
/// saved address with no pin, so the app must look it up instead of using a stored coordinate. The addresses are
/// public buildings, never a real household; they are applied only to a fictional example family on explicit
/// request (`-demoAddress`), so default example facts and recorded requests are unchanged.
public enum DemoAddressCheck: String, Sendable, CaseIterable {
    /// A complete public address (Fort Worth Central Library) that should resolve to one place.
    case resolvable
    /// A street number and name with no city or state, which matches many US places and should ask for review.
    case ambiguous

    public var location: PrivateLocation {
        switch self {
        case .resolvable:
            PrivateLocation(addressLine: "500 W 3rd St", city: "Fort Worth", administrativeArea: "TX", postalCode: "76102", countryCode: "US")
        case .ambiguous:
            PrivateLocation(addressLine: "100 Main St", countryCode: "US")
        }
    }
}
