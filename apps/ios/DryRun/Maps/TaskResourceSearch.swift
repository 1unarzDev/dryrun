import Foundation
import Observation
import DryRunCore

/// A nearby place suggested for one open preparation task, with why it matters and what is still unverified.
/// Map listings stay on this phone; nothing here is sent anywhere. A listing confers no official capability.
struct ResourceSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let planID: String
    let taskID: String
    let category: String
    /// Localization key (offline plans) or the plan's own text (Gemini plans).
    let purpose: String
    let unknowns: [String]
    let requiredEvidence: [String]
    let travelMode: String
    let result: AppleMapSearchResult?
    let official: PublicResource?

    var name: String { result?.name ?? official?.name ?? "" }
    var coordinate: GeographicCoordinate? { result?.coordinate ?? official?.planningCoordinate }
}

/// Runs each plan as one bounded search near the saved home: MapKit for ordinary categories, the reviewed official
/// directory for official-only ones. Results inside the plan's radius, nearest first, at most two per plan.
@MainActor
@Observable
final class TaskResourceSearch {
    private(set) var suggestions: [ResourceSuggestion] = []
    private(set) var isLoading = false
    private(set) var searchedPlanIDs: [String] = []
    private var generation = 0
    private var services: [any MapSearching] = []
    private let makeService: @MainActor () -> any MapSearching

    init(makeService: @escaping @MainActor () -> any MapSearching = { AppleMapSearchService() }) { self.makeService = makeService }

    func cancel(clearResults: Bool = false) {
        generation += 1; services.forEach { $0.cancel() }; services = []; isLoading = false
        if clearResults { suggestions = []; searchedPlanIDs = [] }
    }

    func search(plans: [ResourceSearchPlan], home: GeographicCoordinate, official: [PublicResource]) async {
        cancel()
        generation += 1
        let ticket = generation
        isLoading = true
        var found: [ResourceSuggestion] = []
        for plan in plans {
            let radius = plan.maximumDistanceKm * 1000
            func near(_ c: GeographicCoordinate) -> Bool { home.clLocation.distance(from: c.clLocation) <= radius }
            if let query = ResourceSuggestionPlanner.mapQuery(category: plan.category) {
                let service = makeService()
                services.append(service)
                let span = plan.maximumDistanceKm / 55
                let region = MapRegionHint(center: home, spanLatitude: span, spanLongitude: span)
                let results = (try? await service.search(query: query, region: region)) ?? []
                guard ticket == generation else { return }
                for result in results.filter({ near($0.coordinate) })
                    .sorted(by: { home.clLocation.distance(from: $0.coordinate.clLocation) < home.clLocation.distance(from: $1.coordinate.clLocation) })
                    .prefix(2) {
                    found.append(suggestion(plan, result: result, official: nil))
                }
            } else {
                let types = Set(ResourceSuggestionPlanner.officialServiceTypes(category: plan.category))
                for record in official.filter({ types.contains($0.serviceType) && ($0.planningCoordinate.map(near) ?? true) }).prefix(2) {
                    found.append(suggestion(plan, result: nil, official: record))
                }
            }
        }
        guard ticket == generation else { return }
        // The same store can answer two plans; show it once, under the first (most important) task.
        var seen = Set<String>()
        suggestions = found.filter { seen.insert($0.result?.id ?? $0.official?.id ?? $0.id).inserted }
        searchedPlanIDs = plans.map(\.id)
        isLoading = false
    }

    private func suggestion(_ plan: ResourceSearchPlan, result: AppleMapSearchResult?, official: PublicResource?) -> ResourceSuggestion {
        ResourceSuggestion(id: "\(plan.id)|\(result?.id ?? official?.id ?? "")", planID: plan.id, taskID: plan.taskID, category: plan.category,
                           purpose: plan.purpose, unknowns: plan.unknowns, requiredEvidence: plan.requiredEvidence, travelMode: plan.travelMode,
                           result: result, official: official)
    }
}
