import SwiftUI
import DryRunCore

/// Compact rendering of Core's five answers for one place: why it matters to this family, what the source
/// verifies, what is not confirmed, ordinary distance/access, and what to do now. Text only from saved facts.
@MainActor
struct ResourceRelevanceView: View {
    @Environment(AppModel.self) private var model
    let relevance: ResourceRelevance
    /// Preparations the host screen already flags prominently (e.g. "Call to confirm medical power").
    var omitted: Set<ResourceRelevance.Preparation> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let why = reasons
            if !why.isEmpty {
                Label(why.joined(separator: " "), systemImage: "person.2.fill").font(.caption)
            }
            if let service { Text(service).font(.caption).foregroundStyle(.secondary) }
            if let distance = relevance.access.straightLineMeters {
                Text(copy("access.distance").replacingOccurrences(of: "{distance}", with: PlanningMeasurements.distance(
                    meters: distance, countryCode: model.household?.privateLocation?.countryCode, localizer: model.localizer)))
                    .font(.caption)
            }
            if relevance.access.withinOrdinaryRange == false {
                Text(copy("access.beyond")).font(.caption)
            } else if !relevance.access.plannableModes.contains("driving") {
                Text(copy("access.noCar")).font(.caption)
            }
            if !relevance.unknowns.isEmpty {
                Text(copy("notConfirmed").replacingOccurrences(of: "{items}",
                    with: relevance.unknowns.map { copy("unknown.\($0.rawValue)") }.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            let prepare = relevance.prepareNow.filter { !omitted.contains($0) }
            if !prepare.isEmpty {
                Text(copy("doNow").replacingOccurrences(of: "{items}",
                    with: prepare.map { copy("prep.\($0.rawValue)") }.joined(separator: ", ")))
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("places.relevance")
    }

    private func copy(_ key: String) -> String { MapPlanningCopy.text(key, locale: model.locale) }

    private var reasons: [String] {
        let household = model.household
        func person(_ id: String) -> String { household?.people.first { $0.id == id }?.localizedLabel(model.localizer) ?? "" }
        func equipment(_ id: String) -> String { household?.equipment.first { $0.id == id }?.localizedLabel(model.localizer) ?? "" }
        var seen = Set<String>()
        return relevance.reasons.compactMap { reason -> String? in
            let text: String
            switch reason {
            case .placePurpose(let kind): text = copy("why.\(kind.rawValue)")
            case .openTask: return nil
            case .poweredEquipment(let id, _): text = copy("why.power").replacingOccurrences(of: "{equipment}", with: equipment(id))
            case .coldStorage(let id): text = copy("why.cold").replacingOccurrences(of: "{equipment}", with: equipment(id))
            case .heatSensitive(let id): text = copy("why.heatPerson").replacingOccurrences(of: "{person}", with: person(id))
            case .coldSensitive(let id): text = copy("why.coldPerson").replacingOccurrences(of: "{person}", with: person(id))
            case .stepFree(let id): text = copy("why.stepFree").replacingOccurrences(of: "{person}", with: person(id))
            case .pets: text = copy("why.pets")
            }
            return seen.insert(text).inserted ? text : nil
        }
    }

    private var service: String? {
        switch relevance.service {
        case .femaOpenShelter(let date): copy("service.fema").replacingOccurrences(of: "{date}", with: date)
        case .curatedPublic(let source, let date, _):
            copy("service.curated").replacingOccurrences(of: "{source}", with: source).replacingOccurrences(of: "{date}", with: date)
        case .officialDirectory, .mapListing: nil
        }
    }
}
