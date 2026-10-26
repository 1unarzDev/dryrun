import Foundation
import SwiftUI
import MapKit
import Observation
import DryRunCore

/// Map origin from the saved address, so discovery starts automatically without a location-record chore.
/// A saved pin is used as is. A typed address without a pin is looked up with Apple (the same service that
/// completes addresses) and used for this session only when the candidates agree; it is never saved silently.
@MainActor
@Observable
final class HomeOriginResolver {
    struct Key: Hashable {
        let householdID: String
        let homeID: String
        let sessionID: String?
        let location: PrivateLocation?
    }
    private(set) var decision: HomeOriginPolicy.Decision = .noAddress
    private(set) var isResolving = false
    private var resolvedKey: Key?
    private var activeSearch: MKLocalSearch?

    static func key(_ household: HouseholdProfile?, sessionID: String?) -> Key? {
        household.map { Key(householdID: $0.id, homeID: $0.stableHomeID, sessionID: sessionID, location: $0.privateLocation) }
    }

    /// The coordinate for exactly this household and saved location; a previous family's lookup never leaks.
    func coordinate(for key: Key?) -> GeographicCoordinate? {
        if let saved = HomeOriginPolicy.savedCoordinate(key?.location) { return saved }
        guard let key, key == resolvedKey, case .resolvedFromAddress(let coordinate) = decision else { return nil }
        return coordinate
    }

    func decision(for key: Key?) -> HomeOriginPolicy.Decision {
        guard let key else { return .noAddress }
        if HomeOriginPolicy.savedCoordinate(key.location) != nil || HomeOriginPolicy.geocodingQuery(key.location) == nil {
            return HomeOriginPolicy.decide(location: key.location, candidates: nil)
        }
        return key == resolvedKey ? decision : .unresolved
    }

    func resolve(_ key: Key?) async {
        activeSearch?.cancel(); activeSearch = nil
        guard let key else { resolvedKey = nil; decision = .noAddress; isResolving = false; return }
        let initial = HomeOriginPolicy.decide(location: key.location, candidates: nil)
        guard case .unresolved = initial, let query = HomeOriginPolicy.geocodingQuery(key.location) else {
            resolvedKey = key; decision = initial; isResolving = false; return
        }
        if key == resolvedKey, !isResolving { return }
        resolvedKey = key; decision = .unresolved; isResolving = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let search = MKLocalSearch(request: request)
        activeSearch = search
        let items = try? await search.start().mapItems
        guard !Task.isCancelled, resolvedKey == key else { return }
        activeSearch = nil
        let candidates = items?.compactMap { item -> HomeOriginPolicy.Candidate? in
            GeographicCoordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                .map { HomeOriginPolicy.Candidate(coordinate: $0, countryCode: item.placemark.isoCountryCode) }
        }
        decision = HomeOriginPolicy.decide(location: key.location, candidates: candidates)
        isResolving = false
    }

    func cancel() { activeSearch?.cancel(); activeSearch = nil; isResolving = false }
}

/// One line under the map header: where the origin came from, or a single review action when the saved
/// address could not be placed unambiguously. Nothing is shown for a saved pin or a missing address.
@MainActor
struct HomeOriginStatusView: View {
    @Environment(AppModel.self) private var model
    let resolver: HomeOriginResolver
    let key: HomeOriginResolver.Key?
    @State private var reviewing = false

    var body: some View {
        Group {
            switch resolver.decision(for: key) {
            case .saved, .noAddress: EmptyView()
            case .resolvedFromAddress:
                Label(copy("originFromAddress"), systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
            case .ambiguous(let count):
                review(copy("originAmbiguous").replacingOccurrences(of: "{count}", with: String(count)))
            case .unresolved:
                if resolver.isResolving {
                    HStack(spacing: 6) { ProgressView(); Text(copy("locating")).font(.caption) }
                } else { review(copy("originUnresolved")) }
            }
        }
        .accessibilityIdentifier("map.originStatus")
        .sheet(isPresented: $reviewing) { HomeAddressEditorView() }
    }

    private func copy(_ key: String) -> String { MapPlanningCopy.text(key, locale: model.locale) }

    private func review(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(message).font(.caption)
            Spacer(minLength: 8)
            Button(copy("reviewAddress")) { reviewing = true }
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("map.reviewAddress")
        }
    }
}
