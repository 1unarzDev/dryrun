import Foundation

/// The same selected-place text appears in the phone document, PDF body and snapshot legend.
/// Retained contact/source facts never establish current stock, operation or shelter activation.
public enum PlanPlacePresentation {
    public static func lines(for place: SavedPlace, number: Int, localizer l: Localizer) -> [PlanLine] {
        var translated: [LocalizedText] = []
        func text(_ key: String, fallback: String, values: [String: String] = [:]) -> String {
            var value = l.text(key, values)
            if value.isMissing {
                value.text = Localizer.fill(fallback, values); value.resolvedLocale = "en"
                value.isMissing = false; value.reviewState = .reviewed; value.unfilledPlaceholders = []
            }
            translated.append(value)
            return value.text
        }
        func line(_ value: String, key: String) -> PlanLine {
            defer { translated = [] }
            return PlanLine(text: value, style: .normal, key: key, resolvedLocale: translated.first(where: \.isFallback)?.resolvedLocale ?? l.locale,
                isFallback: translated.contains(where: \.isFallback), isDraftTranslation: translated.contains(where: \.needsDraftLabel), sourceIDs: place.sourceIDs ?? [])
        }
        let fallbackPurpose: String
        switch place.purpose {
        case .outsideMeetingPoint: fallbackPurpose = "Outside meetup near home"
        case .backupMeetingPlace: fallbackPurpose = "Backup meetup outside the neighborhood"
        case .fallbackDestination: fallbackPurpose = "Planning destination"
        case .exteriorHydrant: fallbackPurpose = "Exterior hydrant"
        case .homeReference: fallbackPurpose = "Home reference"
        }
        let purpose = text("map.\(place.purpose.rawValue)", fallback: fallbackPurpose)
        let coordinate = place.coordinate.map { "\($0.latitude), \($0.longitude)" }
        var output = [line("\(number). " + [place.label, purpose, place.addressText, place.findingInstructions, coordinate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), key: "private.savedPlace")]
        let contact = [place.contactPhone, place.websiteURL].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !contact.isEmpty { output.append(line(contact, key: "private.savedPlace.contact")) }
        if place.provenance == .officialDirectory || place.provenance == .appleMapsSearch {
            let source = place.sourcePublisher ?? text(place.provenance == .appleMapsSearch ? "map.source.apple" : "map.source.official", fallback: place.provenance == .appleMapsSearch ? "Apple Maps suggestion" : "Public resource reference")
            let sourceLabel = text("map.source.label", fallback: "Source: {source}", values: ["source": source])
            let checked = place.sourceCheckedAt.map { text("help.freshness.checkedOn", fallback: "Source checked: {date}", values: ["date": $0]) }
                ?? text("map.source.checkMissing", fallback: "Source check date not recorded.")
            output.append(line(sourceLabel + " · " + checked, key: "private.savedPlace.source"))
            output.append(line(text("map.savedSourceNote", fallback: "Saved contact details do not confirm current service or shelter activation."), key: "private.savedPlace.status"))
        } else if place.provenance == .fixture {
            output.append(line(text("family.example", fallback: "Fictional example home"), key: "private.savedPlace.fixture"))
        }
        return output
    }
}
