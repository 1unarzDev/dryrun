import SwiftUI
import MapKit
import CoreLocation
import DryRunCore

/// One home-centered planning flow. Persistent private places are independent of the selected sheet.
@MainActor
struct MapPlanningView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store: RegionalResourcesStore
    @State private var camera: MapCameraPosition = .automatic
    @State private var cameraCenter: GeographicCoordinate?
    @State private var selected: MapPlanningDestination?
    @State private var pendingSearchResult: AppleMapSearchResult?
    @State private var deferredPlace: SavedPlace?
    @State private var editedPlace: SavedPlace?
    @State private var showingEditor = false
    @State private var contextualSaveFinished = false
    @State private var deferredDestination: MapPlanningDestination?
    private let initialPurpose: SavedPlacePurpose?
    private let dismissAfterSave: Bool
    /// False when pushed onto an existing navigation stack (a preparation task), so stacks never nest.
    private let embedInNavigation: Bool
    @State private var showingSearch = false
    @State private var showingList = false
    @State private var discovery = NearbyDiscovery()
    @State private var routeRequest = MapRoutePreviewModel()
    @State private var routeEndpoints: MapPlanningRouteEndpoints?
    @State private var mode: MapTravelMode = .walking
    @State private var originID = "home"
    @State private var message: String?
    @State private var radius = 5000.0
    @State private var location = OptionalLocationService()

    init(content: ContentLibrary, client: PublicAPIClient, regionID: String,
         purpose: SavedPlacePurpose? = nil, dismissAfterSave: Bool = false, embedInNavigation: Bool = true) {
        _store = State(initialValue: RegionalResourcesStore(content: content, client: client, regionID: regionID))
        initialPurpose = purpose; self.dismissAfterSave = dismissAfterSave; self.embedInNavigation = embedInNavigation
    }
    init(store: RegionalResourcesStore, purpose: SavedPlacePurpose? = nil, dismissAfterSave: Bool = false, embedInNavigation: Bool = true) {
        _store = State(initialValue: store)
        initialPurpose = purpose; self.dismissAfterSave = dismissAfterSave; self.embedInNavigation = embedInNavigation
    }
    /// Choosing a meeting place is the task itself: a tapped result goes straight to its editor.
    private var choosingMeetup: Bool { initialPurpose == .outsideMeetingPoint || initialPurpose == .backupMeetingPlace }
    private var places: [SavedPlace] { model.savedPlaces.filter { $0.homeID == model.household?.stableHomeID } }
    private var officialResources: [PublicResource] { store.resources(for: model.household?.regionID ?? "") }
    private var route: MapTravelPreview? { routeRequest.result?.preview }
    private var homeCoordinate: GeographicCoordinate? {
        guard let p = model.household?.privateLocation, let lat = p.latitude, let lon = p.longitude else { return nil }
        return GeographicCoordinate(latitude: lat, longitude: lon)
    }
    private var hint: MapRegionHint? { (cameraCenter ?? homeCoordinate).map { MapRegionHint(center: $0, spanLatitude: radius / 55000, spanLongitude: radius / 55000) } }
    private func t(_ key: String) -> String { model.localizer("map.\(key)") }

    var body: some View {
        if embedInNavigation { NavigationStack { content } } else { content }
    }

    private var content: some View {
            VStack(spacing: 0) {
                if let initialPurpose, choosingMeetup {
                    Label(t(initialPurpose.rawValue), systemImage: initialPurpose.mapSymbol)
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 8)
                }
                Text(t("privacy")).font(.caption).foregroundStyle(.secondary).padding(10)
                Picker(t("view"), selection: $showingList) { Text(t("map")).tag(false); Text(t("list")).tag(true) }
                    .pickerStyle(.segmented).padding(.horizontal)
                HStack {
                    Button(t("searchArea")) { Task { await discover() } }
                    if discovery.isLoading { ProgressView(); Button(t("cancel")) { discovery.cancel() } }
                    Spacer()
                    Menu(t("more")) {
                        Button(t("expand")) { radius = min(radius * 2, 80000); Task { await discover() } }
                        Button(t("dropPin")) { newPlace(coordinate: cameraCenter ?? homeCoordinate) }
                        Button(t("textPlace")) { newPlace(coordinate: nil) }.accessibilityIdentifier("map.menu.addText")
                        Button(t("disableDiscovery")) { discovery.cancel(); discovery.enabled = false }
                        Button(t("enableDiscovery")) { discovery.enabled = true; Task { await discover() } }
                    }
                }.font(.callout).padding(10)
                if let error = discovery.error { Text(error).font(.caption).padding(.horizontal) }
                if showingList { placeList } else { map }
                if let route {
                    HStack {
                        Text(model.localizer("map.routeSummary", ["mode": t(route.mode.rawValue), "distance": distance(route.distanceMeters), "duration": PlanningMeasurements.duration(seconds: route.expectedTravelTime, localizer: model.localizer)]))
                        Spacer(); Button(t("clear")) { routeRequest.cancel(clearPreview: true) }
                    }.font(.caption).padding(10)
                }
                if let message { Text(message).font(.caption).padding(10) }
            }
            .navigationTitle(t("title"))
            .toolbar {
                if embedInNavigation {
                    ToolbarItem(placement: .cancellationAction) { Button(t("done")) { dismiss() }.accessibilityIdentifier("map.done") }
                }
                ToolbarItem(placement: .primaryAction) { Button { showingSearch = true } label: { Label(t("search"), systemImage: "magnifyingglass") }.accessibilityIdentifier("map.search") }
            }
            .sheet(isPresented: $showingSearch, onDismiss: { if let pendingSearchResult { select(pendingSearchResult); self.pendingSearchResult = nil } }) {
                MapSearchSheet(region: hint, onSelect: { pendingSearchResult = $0; showingSearch = false })
            }
            .sheet(item: $selected, onDismiss: { if let deferredPlace { editedPlace = deferredPlace; self.deferredPlace = nil; showingEditor = true } }) { result in destinationSheet(result) }
            .sheet(isPresented: $showingEditor, onDismiss: {
                if contextualSaveFinished && dismissAfterSave { contextualSaveFinished = false; dismiss() }
                else if let deferredDestination { selected = deferredDestination; self.deferredDestination = nil }
            }) {
                if let editedPlace { PlaceEditorView(place: editedPlace, onSaved: { contextualSaveFinished = true }, onDirections: { place in
                    guard place.coordinate != nil else { return }
                    deferredDestination = MapPlanningDestination(place: place)
                }) }
            }
            .task(id: homeCoordinate) {
                discovery.cancel(clearResults: true); invalidateChangedRouteEndpoints(); cameraCenter = nil
                if let homeCoordinate {
                    let newHomeRegion = MapRegionHint(center: homeCoordinate, spanLatitude: radius / 55000, spanLongitude: radius / 55000)
                    camera = .region(newHomeRegion.mapRegion)
                    await discovery.search(region: newHomeRegion, locale: model.locale)
                }
            }
            .onChange(of: selected?.id) { _, _ in routeRequest.cancel() }
            .onChange(of: originID) { _, _ in routeRequest.cancel(clearPreview: true) }
            .onChange(of: mode) { _, _ in routeRequest.cancel(clearPreview: true) }
            .onChange(of: places) { _, _ in invalidateChangedRouteEndpoints() }
            .onChange(of: routeRequest.result) { _, result in
                guard let result else { return }
                guard selected?.id == result.destinationID else { routeRequest.cancel(clearPreview: true); return }
                selected = nil
                var rect = MKMapRect.null
                for point in ([result.origin, result.destination] + result.preview.coordinates) {
                    let p = MKMapPoint(point.cl); rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
                }
                camera = .rect(rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15))
            }
            .onDisappear { discovery.cancel(); routeRequest.cancel() }
    }

    private var map: some View {
        Map(position: $camera) {
            if let homeCoordinate { Marker(t("home"), systemImage: "house.fill", coordinate: homeCoordinate.cl).tint(.indigo) }
            ForEach(places) { place in
                if let coordinate = place.coordinate {
                    Annotation(place.label, coordinate: coordinate.cl) {
                        Button { editedPlace = place; showingEditor = true } label: { Image(systemName: place.purpose.mapSymbol).font(.title).foregroundStyle(place.purpose.mapColor).background(.background, in: Circle()) }
                            .accessibilityLabel(place.label)
                    }
                }
            }
            ForEach(discovery.results) { result in
                Annotation(result.name, coordinate: result.coordinate.cl) { Button { select(result) } label: { Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.orange).background(.background, in: Circle()) }.accessibilityLabel(result.name) }
            }
            ForEach(officialResources.filter { resource in !places.contains { $0.provenance == .officialDirectory && $0.sourceResourceID == resource.id } }) { resource in
                if let coordinate = resource.planningCoordinate {
                    Annotation(resource.name, coordinate: coordinate.cl) {
                        Button { select(resource) } label: {
                            Image(systemName: "building.2.crop.circle.fill").font(.title2).foregroundStyle(.teal).background(.background, in: Circle())
                        }.accessibilityLabel(resource.name)
                    }
                }
            }
            if let route { MapPolyline(coordinates: route.coordinates.map(\.cl)).stroke(.blue, lineWidth: 4) }
        }
        .mapStyle(.standard(pointsOfInterest: .all))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in cameraCenter = GeographicCoordinate(latitude: context.region.center.latitude, longitude: context.region.center.longitude) }
        .overlay(alignment: .bottom) { if homeCoordinate == nil && places.isEmpty && discovery.results.isEmpty { Text(t("noHome")).font(.callout).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding() } }
        .accessibilityLabel(t("mapSummary"))
    }

    private var placeList: some View {
        List {
            if let address = model.household?.privateLocation?.addressLine { Section(t("home")) { Text(address) } }
            Section(t("saved")) {
                ForEach(places) { place in
                    Button { editedPlace = place; showingEditor = true } label: {
                        VStack(alignment: .leading) { Text(place.label).font(.headline); Text(t(place.purpose.rawValue)).font(.caption); if let address = place.addressText { Text(address) }; if let instructions = place.findingInstructions { Text(instructions) } }
                    }.buttonStyle(.plain)
                }
                Button(t("textPlace")) { newPlace(coordinate: nil) }.accessibilityIdentifier("map.addText")
            }
            Section(t("suggestions")) {
                if discovery.results.isEmpty { Text(discovery.isLoading ? t("searching") : t("empty")).foregroundStyle(.secondary) }
                ForEach(discovery.results) { result in
                    Button { select(result) } label: { VStack(alignment: .leading) {
                        Text(result.name).font(.headline); Text(t(["hospital", "pharmacy", "grocery"].contains(result.category ?? "") ? result.category! : "suggestion")); if let address = result.address { Text(address).font(.caption) }
                        if let homeCoordinate { Text(distance(homeCoordinate.clLocation.distance(from: result.coordinate.clLocation))).font(.caption) }
                    } }.buttonStyle(.plain)
                }
            }
            if store.regionInfo(for: model.household?.regionID ?? "") != nil {
                Section(t("official")) { ForEach(officialResources) { resource in
                    Button { select(resource) } label: {
                        VStack(alignment: .leading) {
                            Text(resource.name).font(.headline)
                            Text(model.localizer("help.service.\(resource.serviceType.rawValue)")).font(.caption)
                            Text(resource.summary).font(.caption)
                            if model.locale != "en" { Text(model.localizer("common.fallbackShown")).font(.caption) }
                            if let phone = resource.contact.phone { Text(phone) }
                            if let address = resource.contact.address { Text(address) }
                            if let homeCoordinate, let coordinate = resource.planningCoordinate {
                                Text(distance(homeCoordinate.clLocation.distance(from: coordinate.clLocation))).font(.caption)
                            }
                            Text("\(resource.publisher) · \(resource.checkedAt)").font(.caption2)
                        }
                    }.buttonStyle(.plain)
                } }
            }
            Section { Text(t("offline")).font(.footnote) }
        }
    }

    private func destinationSheet(_ result: MapPlanningDestination) -> some View {
        let place = result.place
        return NavigationStack {
            Form {
                Section {
                    Text(place.label).font(.headline)
                    if let address = place.addressText { Text(address) }
                    if let resource = result.officialResource {
                        Text(model.localizer("help.service.\(resource.serviceType.rawValue)"))
                        Text(resource.summary).font(.callout)
                        if model.locale != "en" { Text(model.localizer("common.fallbackShown")).font(.caption) }
                        if resource.reviewState != .reviewed { Text(model.localizer("help.review.needsReview")).font(.caption) }
                        if resource.classification == .demo || resource.classification == .fixture { Text(model.localizer("help.freshness.demo")).font(.caption) }
                        let activation = PublicDataPolicy.activationDisplay(for: resource, now: Date())
                        if activation != .notApplicable {
                            Text(model.localizer(activation == .confirmedActive ? "help.activation.status.active" : activation == .confirmedInactive ? "help.activation.status.inactive" : "help.activation.unconfirmed")).font(.caption.weight(.semibold))
                        }
                    } else { Text(t(place.provenance == .appleMapsSearch ? "suggestionNote" : "savedSourceNote")).font(.caption) }
                    if let publisher = place.sourcePublisher { Text(publisher).font(.caption) }
                    if let checked = place.sourceCheckedAt { Text(model.localizer("help.freshness.checkedOn", ["date": checked])).font(.caption) }
                }
                if let phone = place.contactPhone, let url = PhoneLink.url(phone) {
                    Section(t("contact")) { Link(destination: url) { Label(phone, systemImage: "phone") } }
                }
                if let website = place.websiteURL, let url = URL(string: website) { Link(t("website"), destination: url) }
                if place.coordinate != nil {
                    Section(t("directions")) {
                        Picker(t("origin"), selection: $originID) {
                            if homeCoordinate != nil { Text(t("home")).tag("home") }
                            ForEach(places.filter { $0.coordinate != nil }) { Text($0.label).tag($0.id) }
                            Text(t("current")).tag("current")
                        }
                        Picker(t("mode"), selection: $mode) { ForEach(MapTravelMode.allCases) { Text(t($0.rawValue)).tag($0) } }
                        Button(t("preview")) { preview(result) }.disabled(routeRequest.isLoading)
                        if let key = routeRequest.errorKey { Text(t(key)).font(.caption).foregroundStyle(.secondary) }
                        Text(t("routeNote")).font(.caption)
                    }
                } else { Section { Text(t("noCoordinateDirections")).font(.caption) } }
                Section {
                    Button(t("save")) { deferredPlace = place; selected = nil }
                    if let coordinate = place.coordinate {
                        Button(t("openApple")) { let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.cl)); item.name = place.label; item.openInMaps() }
                    }
                }
            }
            .navigationTitle(t("destination"))
            .onAppear { if originID == "home" && homeCoordinate == nil { originID = places.first(where: { $0.coordinate != nil })?.id ?? "current" } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("done")) { routeRequest.cancel(); selected = nil } } }
        }
    }
    private func select(_ result: AppleMapSearchResult) {
        guard let household = model.household else { return }
        let place = SavedPlace.appleSuggestion(sourceID: result.id, name: result.name, coordinate: result.coordinate,
            address: result.address, phone: result.phone, website: result.website, homeID: household.stableHomeID,
            purpose: initialPurpose ?? .fallbackDestination)
        if choosingMeetup { editedPlace = place; showingEditor = true } else { selected = MapPlanningDestination(place: place) }
    }
    private func select(_ resource: PublicResource) {
        guard let household = model.household else { return }
        let place = SavedPlace.officialResource(resource, homeID: household.stableHomeID, purpose: initialPurpose ?? .fallbackDestination)
        if choosingMeetup { editedPlace = place; showingEditor = true } else { selected = MapPlanningDestination(place: place, officialResource: resource) }
    }
    private func discover() async {
        guard discovery.enabled, let hint else { message = t("noHome"); return }
        await discovery.search(region: hint, locale: model.locale)
    }
    private func distance(_ meters: Double) -> String {
        PlanningMeasurements.distance(meters: meters, countryCode: model.household?.privateLocation?.countryCode, localizer: model.localizer)
    }
    private func newPlace(coordinate: GeographicCoordinate?, label: String = "", address: String? = nil, provenance: SavedPlaceProvenance = .userSelected) {
        guard let household = model.household else { return }
        let place = SavedPlace(homeID: household.stableHomeID, purpose: initialPurpose ?? .fallbackDestination, label: label, coordinate: coordinate, addressText: address, provenance: provenance)
        if selected != nil { deferredPlace = place; selected = nil }
        else { editedPlace = place; showingEditor = true }
    }
    private func preview(_ destination: MapPlanningDestination) {
        guard let coordinate = destination.place.coordinate else { return }
        let selectedOriginID = originID
        let savedOrigin = selectedOriginID == "home" ? homeCoordinate : places.first { $0.id == selectedOriginID }?.coordinate
        let origin: MapPlanningRouteEndpoints.Reference
        if selectedOriginID == "home", let homeCoordinate { origin = .home(homeCoordinate) }
        else if selectedOriginID != "current", let savedOrigin { origin = .savedPlace(id: selectedOriginID, coordinate: savedOrigin) }
        else { origin = .external }
        let target: MapPlanningRouteEndpoints.Reference = places.contains(where: { $0.id == destination.id })
            ? .savedPlace(id: destination.id, coordinate: coordinate) : .external
        routeEndpoints = MapPlanningRouteEndpoints(origin: origin, destination: target)
        routeRequest.start(destinationID: destination.id, destination: coordinate, mode: mode) {
            if selectedOriginID == "current" {
                guard let current = await location.requestOneShot() else { return nil }
                return GeographicCoordinate(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude)
            }
            return savedOrigin
        }
    }

    private func invalidateChangedRouteEndpoints() {
        guard let routeEndpoints, !routeEndpoints.isCurrent(homeCoordinate: homeCoordinate, places: places) else { return }
        routeRequest.cancel(clearPreview: true)
        self.routeEndpoints = nil
    }
}

extension GeographicCoordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

@MainActor
struct PlaceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var place: SavedPlace
    var onSaved: (() -> Void)? = nil
    var onDirections: ((SavedPlace) -> Void)? = nil
    @State private var saving = false
    @State private var error: String?
    @State private var confirmingDelete = false
    private func t(_ key: String) -> String { model.localizer("map.\(key)") }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField(t("label"), text: $place.label).accessibilityIdentifier("place.name"); Picker(t("purpose"), selection: $place.purpose) { ForEach(SavedPlacePurpose.allCases, id: \.self) { Text(t($0.rawValue)).tag($0) } }.accessibilityIdentifier("place.purpose"); TextField(t("address"), text: Binding(get: { place.addressText ?? "" }, set: { place.addressText = $0 })).accessibilityIdentifier("place.address"); TextField(t("instructions"), text: Binding(get: { place.findingInstructions ?? "" }, set: { place.findingInstructions = $0 }), axis: .vertical).accessibilityIdentifier("place.instructions") }
                if let coordinate = place.coordinate { Section(t("pin")) { Text("\(coordinate.latitude), \(coordinate.longitude)").font(.caption); Button(t("directions")) { onDirections?(place); dismiss() }.disabled(onDirections == nil) } }
                if place.provenance == .officialDirectory || place.provenance == .appleMapsSearch {
                    Section(t("contact")) {
                        Text(t("savedSourceNote")).font(.caption)
                        if let publisher = place.sourcePublisher { Text(publisher).font(.caption) }
                        if let checked = place.sourceCheckedAt { Text(model.localizer("help.freshness.checkedOn", ["date": checked])).font(.caption) }
                        if let phone = place.contactPhone {
                            Text(phone).textSelection(.enabled)
                            if let url = PhoneLink.url(phone) { Link(model.localizer("common.help.call"), destination: url) }
                        }
                        if let website = place.websiteURL, let url = URL(string: website) { Link(t("website"), destination: url) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if model.savedPlaces.contains(where: { $0.id == place.id }) { Button(t("delete"), role: .destructive) { confirmingDelete = true } }
            }.navigationTitle(t("save"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(t("save")) { saving = true; place.updatedAt = Date(); Task { if await model.savePlace(place) { onSaved?(); dismiss() } else { error = t("saveError") }; saving = false } }.disabled(saving || place.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("place.save") }
                }
                .confirmationDialog(t("delete"), isPresented: $confirmingDelete, titleVisibility: .visible) { Button(t("delete"), role: .destructive) { Task { await model.deletePlace(id: place.id); if !model.savedPlaces.contains(where: { $0.id == place.id }) { dismiss() } else { error = t("saveError") } } } }
        }
    }
}

@MainActor
private struct MapSearchSheet: View {
    @Environment(AppModel.self) private var model
    let region: MapRegionHint?
    let onSelect: (AppleMapSearchResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [AppleMapSearchResult] = []
    @State private var error: String?
    @State private var generation = 0
    private let service = AppleMapSearchService()
    var body: some View {
        NavigationStack { List {
            Text(model.localizer("map.privacy")).font(.caption)
            TextField(model.localizer("map.search"), text: $query).onSubmit(search)
            Button(model.localizer("map.search"), action: search)
            if let error { Text(error) }
            ForEach(results) { result in Button { dismiss(); onSelect(result) } label: { VStack(alignment: .leading) { Text(result.name); if let address = result.address { Text(address).font(.caption) } } } }
        }.navigationTitle(model.localizer("map.search")).toolbar { Button(model.localizer("map.cancel")) { dismiss() } } }
        .onChange(of: query) { _, _ in generation += 1; service.cancel() }
        .onDisappear { generation += 1; service.cancel() }
    }
    private func search() {
        generation += 1; let ticket = generation; let text = query
        Task { do { let found = try await service.search(query: text, region: region); guard ticket == generation else { return }; results = found; error = found.isEmpty ? model.localizer("map.empty") : nil } catch { if ticket == generation { self.error = model.localizer("map.searchError") } } }
    }
}


private extension SavedPlacePurpose {
    var mapSymbol: String {
        switch self {
        case .outsideMeetingPoint: "person.2.circle.fill"
        case .backupMeetingPlace: "flag.circle.fill"
        case .fallbackDestination: "cross.case.circle.fill"
        case .exteriorHydrant: "drop.circle.fill"
        case .homeReference: "house.circle.fill"
        }
    }
    var mapColor: Color {
        switch self { case .outsideMeetingPoint: .green; case .backupMeetingPlace: .purple; case .fallbackDestination: .orange; case .exteriorHydrant: .red; case .homeReference: .indigo }
    }
}
