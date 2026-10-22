import SwiftUI
import MapKit
import DryRunCore

/// Prepare → Where to go: FEMA open shelters and curated cooling centers near the saved home, each with its source;
/// accessibility only as the source states it; "call to confirm medical power" for households with powered needs;
/// a driving or walking route from Apple Maps. Only the public facility addresses and the chosen endpoints go to
/// Apple; FEMA receives a statewide query with no location.
@MainActor
struct WhereToGoView: View {
    @Environment(AppModel.self) private var model
    @State private var places: [PublicPlace] = []
    @State private var femaState: FemaState = .loading
    @State private var selected: PublicPlace.ID?
    @State private var walking = true
    @State private var route: MKRoute?
    @State private var routeFailed = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var activeDirections: MKDirections?
    @State private var resolver = HomeOriginResolver()
    let context: MapPlanningContext

    init(context: MapPlanningContext = MapPlanningContext()) { self.context = context }

    enum FemaState { case loading, loaded(Int), unavailable }

    private var planningScope: MapPlanningScope? {
        model.household.map { MapPlanningScope(householdID: $0.id, homeID: $0.stableHomeID,
            isExample: $0.isFictional, homeCoordinate: origin.flatMap {
                GeographicCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }, sessionID: model.scopeSessionID) }
    }
    private struct RouteKey: Hashable {
        let scope: MapPlanningScope?
        let destination: PublicPlace.ID?
        let walking: Bool
        let context: MapPlanningContext
    }
    private var routeKey: RouteKey { RouteKey(scope: planningScope, destination: selected, walking: walking, context: context) }

    private var originKey: HomeOriginResolver.Key? { HomeOriginResolver.key(model.household, sessionID: model.scopeSessionID) }
    /// Saved pin, or the saved address placed by Apple when its candidates agree (this session only).
    private var origin: CLLocationCoordinate2D? {
        resolver.coordinate(for: originKey).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
    private var originCoordinate: GeographicCoordinate? { resolver.coordinate(for: originKey) }

    var body: some View {
        let l = model.localizer
        List {
            Section {
                Text(l("places.intro")).font(.callout)
                if context.intent != .ordinary || context.phase != .advance {
                    let key = context.phase == .advance && (context.intent == .tornadoShelter || context.intent == .structureFire)
                        ? context.intent.rawValue + "Advance" : context.intent.rawValue
                    Text(MapPlanningCopy.text(key, locale: model.locale)).font(.callout)
                    if context.phase == .simulation { Text(MapPlanningCopy.text("simulation", locale: model.locale)).font(.caption) }
                }
                if let address = model.household?.privateLocation?.addressLine, origin != nil {
                    Label(l("places.from", ["place": address]), systemImage: "house").font(.footnote)
                } else if HomeOriginPolicy.geocodingQuery(model.household?.privateLocation) == nil {
                    Text(l("places.noOrigin")).font(.footnote).foregroundStyle(.secondary)
                }
                HomeOriginStatusView(resolver: resolver, key: originKey)
            }
            Section {
                map.frame(height: 300).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("places.map")
                if origin != nil, selected != nil, context.allowsOrdinaryDirections {
                    Picker(l("places.route"), selection: $walking) {
                        if model.household.map({ HouseholdContextSnapshot($0).transport }) != "noCar" {
                            Text(l("places.drive")).tag(false)
                        }
                        Text(l("places.walk")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    if let route {
                        Label(l("places.routeSummary", ["time": Duration.seconds(route.expectedTravelTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)),
                                                        "distance": Measurement(value: route.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))]),
                              systemImage: walking ? "figure.walk" : "car.fill")
                            .font(.headline)
                            .accessibilityIdentifier("places.routeSummary")
                    } else if routeFailed {
                        Text(l("places.routeFailed")).font(.footnote)
                    } else {
                        ProgressView()
                    }
                    Text(l("places.routeNote")).font(.caption).foregroundStyle(.secondary)
                }
            }
            let notes = model.household.map(PublicPlaces.householdNotes) ?? []
            if !notes.isEmpty {
                Section(l("places.forHousehold")) {
                    ForEach(notes, id: \.id) { note in
                        Label(model.alertStepText(note, prefix: "places.note."), systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.callout)
                    }
                }
                .accessibilityIdentifier("places.householdNotes")
            }
            Section {
                switch femaState {
                case .loading: ProgressView()
                case .loaded(0): Text(l("places.noShelters")).font(.footnote).foregroundStyle(.secondary)
                case .loaded: EmptyView()
                case .unavailable: Text(l("places.sheltersUnavailable")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(places) { place in row(place) }
            }
        }
        .navigationTitle(l("places.title"))
        .task(id: planningScope) {
            activeDirections?.cancel(); activeDirections = nil
            places = []; selected = nil; route = nil; routeFailed = false
            femaState = .loading; walking = true; camera = .automatic
            await load()
        }
        .task(id: routeKey) { await computeRoute() }
        .task(id: originKey) { await resolver.resolve(originKey) }
        .onDisappear { activeDirections?.cancel(); activeDirections = nil; resolver.cancel() }
    }

    private var map: some View {
        Map(position: $camera, selection: $selected) {
            if let origin {
                Annotation(model.localizer("common.tab.home"), coordinate: origin) {
                    Image(systemName: "house.fill").padding(6).background(.blue, in: Circle()).foregroundStyle(.white)
                }
            }
            ForEach(places.filter { $0.latitude != nil }) { place in
                Marker(place.name, systemImage: place.kind == .openShelter ? "house.lodge.fill" : "snowflake",
                       coordinate: CLLocationCoordinate2D(latitude: place.latitude!, longitude: place.longitude!))
                    .tint(place.kind == .openShelter ? .red : .teal)
                    .tag(place.id)
            }
            if let route { MapPolyline(route).stroke(.blue, lineWidth: 5) }
        }
    }

    private func row(_ place: PublicPlace) -> some View {
        let l = model.localizer
        let relevance = model.household.map { ResourceRelevancePolicy.forPublicPlace(place, household: $0, origin: originCoordinate) }
        let powered = relevance?.prepareNow.contains(.confirmMedicalPower) == true
        return Button { selected = place.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(place.name).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    if selected == place.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                }
                Text(l("places.kind.\(place.kind.rawValue)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(place.address).font(.footnote).foregroundStyle(.secondary)
                // The seasonal role as the curated source words it: never presented as open now.
                if let role = place.role { Text(role).font(.caption).foregroundStyle(.secondary) }
                if place.stated.isEmpty {
                    Text(l("places.noAccessInfo")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(place.stated, id: \.fact) { fact in
                        // FEMA wording names FEMA; a curated page's statement is attributed to that source.
                        Label(place.kind == .openShelter ? l("places.stated.\(fact.fact).\(fact.value)")
                                : MapPlanningCopy.text("stated.\(fact.fact).\(fact.value)", locale: model.locale),
                              systemImage: fact.value ? "figure.roll" : "exclamationmark.triangle")
                            .font(.caption)
                    }
                }
                if let relevance { ResourceRelevanceView(relevance: relevance, omitted: [.confirmMedicalPower]) }
                if let pets = place.petsAsPublished { Text(l("places.pets", ["text": pets])).font(.caption) }
                if powered {
                    Label(l("places.callPower"), systemImage: "bolt.heart").font(.caption.weight(.semibold)).foregroundStyle(Theme.caution)
                }
                if let phone = place.phone, let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                    Link(l("places.call", ["phone": phone]), destination: url).font(.caption.weight(.semibold))
                }
                Text(l("places.source", ["source": place.source, "date": place.retrievedAt])).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("places.place.\(place.id)")
    }

    private func load() async {
        let scope = planningScope
        var curated = (try? ContentLocator.contentRoot()).flatMap { try? Data(contentsOf: $0.appendingPathComponent("places/tarrant-v1.json")) }
            .flatMap { try? PublicPlaces.curated($0) } ?? []
        // Public facility addresses only; the household's own address is never searched here.
        for index in curated.indices {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = curated[index].address
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                curated[index].latitude = item.placemark.coordinate.latitude
                curated[index].longitude = item.placemark.coordinate.longitude
            }
            guard !Task.isCancelled, scope == planningScope else { return }
        }
        var shelters: [PublicPlace] = []
        if let fema = await Self.fetchFemaTexas() {
            shelters = fema
        } else {
            guard !Task.isCancelled, scope == planningScope else { return }
            femaState = .unavailable
        }
        guard !Task.isCancelled, scope == planningScope else { return }
        let all = shelters + curated
        if let origin {
            let nearby = PublicPlaces.near(all, latitude: origin.latitude, longitude: origin.longitude, kilometers: 80)
            places = ResourceRelevancePolicy.order(nearby, context: context)
            if case .loading = femaState { femaState = .loaded(nearby.filter { $0.kind == .openShelter }.count) }
        } else {
            places = ResourceRelevancePolicy.order(all.filter { $0.kind != .openShelter } + all.filter { $0.kind == .openShelter }.prefix(20), context: context)
            if case .loading = femaState { femaState = .loaded(shelters.count) }
        }
        if selected == nil { selected = places.first { $0.latitude != nil }?.id }
    }

    /// FEMA's open Texas shelters (statewide query; no household location is sent).
    static func fetchFemaTexas() async -> [PublicPlace]? {
        var components = URLComponents(string: "https://gis.fema.gov/arcgis/rest/services/NSS/OpenShelters/FeatureServer/0/query")!
        components.queryItems = [.init(name: "where", value: "state='TX'"), .init(name: "outFields", value: "*"),
                                 .init(name: "returnGeometry", value: "false"), .init(name: "f", value: "json")]
        guard let url = components.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? PublicPlaces.femaShelters(data, retrievedAt: Date().formatted(.iso8601.year().month().day()))
    }

    private func computeRoute() async {
        activeDirections?.cancel(); activeDirections = nil
        route = nil; routeFailed = false
        guard context.allowsOrdinaryDirections, let origin, let place = places.first(where: { $0.id == selected }), let lat = place.latitude, let lon = place.longitude else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        request.transportType = walking ? .walking : .automobile
        let target = routeKey
        let directions = MKDirections(request: request)
        activeDirections = directions
        do {
            let result = try await directions.calculate()
            guard !Task.isCancelled, target == routeKey else { return }
            route = result.routes.first
            routeFailed = route == nil
            if let route { camera = .rect(route.polyline.boundingMapRect.insetBy(dx: -2000, dy: -2000)) }
        } catch {
            if !Task.isCancelled, target == routeKey { routeFailed = true }
        }
    }
}

/// The Prepare entry to the map.
struct WhereToGoEntryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink { WhereToGoView() } label: {
            SectionCard(title: model.localizer("places.open"), systemImage: "map.fill") {
                Text(model.localizer("places.intro")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("next.whereToGo")
    }
}
