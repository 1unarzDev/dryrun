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
    @State private var selected: AppleMapSearchResult?
    @State private var pendingSearchResult: AppleMapSearchResult?
    @State private var deferredPlace: SavedPlace?
    @State private var editedPlace: SavedPlace?
    @State private var showingEditor = false
    @State private var contextualSaveFinished = false
    @State private var deferredDestination: AppleMapSearchResult?
    private let initialPurpose: SavedPlacePurpose?
    private let dismissAfterSave: Bool
    @State private var showingSearch = false
    @State private var showingList = false
    @State private var discovery = NearbyDiscovery()
    @State private var routeRequest = MapRoutePreviewModel()
    @State private var mode: MapTravelMode = .walking
    @State private var originID = "home"
    @State private var message: String?
    @State private var radius = 5000.0
    @State private var location = OptionalLocationService()

    init(content: ContentLibrary, client: PublicAPIClient, regionID: String,
         purpose: SavedPlacePurpose? = nil, dismissAfterSave: Bool = false) {
        _store = State(initialValue: RegionalResourcesStore(content: content, client: client, regionID: regionID))
        initialPurpose = purpose; self.dismissAfterSave = dismissAfterSave
    }
    init(store: RegionalResourcesStore, purpose: SavedPlacePurpose? = nil, dismissAfterSave: Bool = false) {
        _store = State(initialValue: store)
        initialPurpose = purpose; self.dismissAfterSave = dismissAfterSave
    }
    private var places: [SavedPlace] { model.savedPlaces.filter { $0.homeID == model.household?.stableHomeID } }
    private var route: MapTravelPreview? { routeRequest.result?.preview }
    private var homeCoordinate: GeographicCoordinate? {
        guard let p = model.household?.privateLocation, let lat = p.latitude, let lon = p.longitude else { return nil }
        return GeographicCoordinate(latitude: lat, longitude: lon)
    }
    private var hint: MapRegionHint? { (cameraCenter ?? homeCoordinate).map { MapRegionHint(center: $0, spanLatitude: radius / 55000, spanLongitude: radius / 55000) } }
    private func t(_ key: String) -> String { model.localizer("map.\(key)") }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                        Button(t("textPlace")) { newPlace(coordinate: nil) }
                        Button(t("disableDiscovery")) { discovery.cancel(); discovery.enabled = false }
                        Button(t("enableDiscovery")) { discovery.enabled = true; Task { await discover() } }
                    }
                }.font(.callout).padding(10)
                if let error = discovery.error { Text(error).font(.caption).padding(.horizontal) }
                if showingList { placeList } else { map }
                if let route {
                    HStack {
                        Text("\(t(route.mode.rawValue)): \(Measurement(value: route.distanceMeters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))) · \(Int((route.expectedTravelTime / 60).rounded(.up))) min")
                        Spacer(); Button(t("clear")) { routeRequest.cancel(clearPreview: true) }
                    }.font(.caption).padding(10)
                }
                if let message { Text(message).font(.caption).padding(10) }
            }
            .navigationTitle(t("title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showingSearch = true } label: { Label(t("search"), systemImage: "magnifyingglass") }.accessibilityIdentifier("map.search") }
            }
            .sheet(isPresented: $showingSearch, onDismiss: { if let pendingSearchResult { selected = pendingSearchResult; self.pendingSearchResult = nil } }) {
                MapSearchSheet(region: hint, onSelect: { pendingSearchResult = $0; showingSearch = false })
            }
            .sheet(item: $selected, onDismiss: { if let deferredPlace { editedPlace = deferredPlace; self.deferredPlace = nil; showingEditor = true } }) { result in destinationSheet(result) }
            .sheet(isPresented: $showingEditor, onDismiss: {
                if contextualSaveFinished && dismissAfterSave { contextualSaveFinished = false; dismiss() }
                else if let deferredDestination { selected = deferredDestination; self.deferredDestination = nil }
            }) {
                if let editedPlace { PlaceEditorView(place: editedPlace, onSaved: { contextualSaveFinished = true }, onDirections: { place in
                    guard let coordinate = place.coordinate else { return }
                    deferredDestination = AppleMapSearchResult(id: place.id, name: place.label, coordinate: coordinate, address: place.addressText, category: nil)
                }) }
            }
            .task(id: homeCoordinate) {
                discovery.cancel(clearResults: true); routeRequest.cancel(clearPreview: true); cameraCenter = nil
                if let homeCoordinate {
                    let newHomeRegion = MapRegionHint(center: homeCoordinate, spanLatitude: radius / 55000, spanLongitude: radius / 55000)
                    camera = .region(newHomeRegion.mapRegion)
                    await discovery.search(region: newHomeRegion, locale: model.locale)
                }
            }
            .onChange(of: selected?.id) { _, _ in routeRequest.cancel() }
            .onChange(of: originID) { _, _ in routeRequest.cancel(clearPreview: true) }
            .onChange(of: mode) { _, _ in routeRequest.cancel(clearPreview: true) }
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
                Annotation(result.name, coordinate: result.coordinate.cl) { Button { selected = result } label: { Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.orange).background(.background, in: Circle()) }.accessibilityLabel(result.name) }
            }
            if let route { MapPolyline(coordinates: route.coordinates.map(\.cl)).stroke(.blue, lineWidth: 4) }
        }
        .mapStyle(.standard(pointsOfInterest: .includingAll))
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
                Button(t("textPlace")) { newPlace(coordinate: nil) }
            }
            Section(t("suggestions")) {
                if discovery.results.isEmpty { Text(discovery.isLoading ? t("searching") : t("empty")).foregroundStyle(.secondary) }
                ForEach(discovery.results) { result in
                    Button { selected = result } label: { VStack(alignment: .leading) {
                        Text(result.name).font(.headline); Text(t(["hospital", "pharmacy", "grocery"].contains(result.category ?? "") ? result.category! : "suggestion")); if let address = result.address { Text(address).font(.caption) }
                        if let homeCoordinate { Text(Measurement(value: homeCoordinate.clLocation.distance(from: result.coordinate.clLocation), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))).font(.caption) }
                    } }.buttonStyle(.plain)
                }
            }
            if store.regionInfo(for: model.household?.regionID ?? "") != nil {
                Section(t("official")) { ForEach(store.resources(for: model.household?.regionID ?? "")) { resource in
                    VStack(alignment: .leading) { Text(resource.name).font(.headline); Text(resource.summary).font(.caption); if let phone = resource.contact.phone { Text(phone) }; if let address = resource.contact.address { Text(address) }; Text("\(resource.publisher) · \(resource.checkedAt)").font(.caption2) }
                } }
            }
            Section { Text(t("offline")).font(.footnote) }
        }
    }

    private func destinationSheet(_ result: AppleMapSearchResult) -> some View {
        NavigationStack {
            Form {
                Section { Text(result.name).font(.headline); if let address = result.address { Text(address) }; Text(t("suggestionNote")).font(.caption) }
                if let phone = result.phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                    Section(t("contact")) { Link(destination: url) { Label(phone, systemImage: "phone") } }
                }
                if let website = result.website, let url = URL(string: website) { Link(t("website"), destination: url) }
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
                Section {
                    Button(t("save")) { newPlace(coordinate: result.coordinate, label: result.name, address: result.address, provenance: .appleMapsSearch) }
                    Button(t("openApple")) { let item = MKMapItem(placemark: MKPlacemark(coordinate: result.coordinate.cl)); item.name = result.name; item.openInMaps() }
                }
            }
            .navigationTitle(t("destination"))
            .onAppear { if originID == "home" && homeCoordinate == nil { originID = places.first(where: { $0.coordinate != nil })?.id ?? "current" } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("done")) { routeRequest.cancel(); selected = nil } } }
        }
    }
    private func discover() async {
        guard discovery.enabled, let hint else { message = t("noHome"); return }
        await discovery.search(region: hint, locale: model.locale)
    }
    private func newPlace(coordinate: GeographicCoordinate?, label: String = "", address: String? = nil, provenance: SavedPlaceProvenance = .userSelected) {
        guard let household = model.household else { return }
        let place = SavedPlace(homeID: household.stableHomeID, purpose: initialPurpose ?? .fallbackDestination, label: label, coordinate: coordinate, addressText: address, provenance: provenance)
        if selected != nil { deferredPlace = place; selected = nil }
        else { editedPlace = place; showingEditor = true }
    }
    private func preview(_ destination: AppleMapSearchResult) {
        let selectedOriginID = originID
        let savedOrigin = selectedOriginID == "home" ? homeCoordinate : places.first { $0.id == selectedOriginID }?.coordinate
        routeRequest.start(destinationID: destination.id, destination: destination.coordinate, mode: mode) {
            if selectedOriginID == "current" {
                guard let current = await location.requestOneShot() else { return nil }
                return GeographicCoordinate(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude)
            }
            return savedOrigin
        }
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
                Section { TextField(t("label"), text: $place.label); Picker(t("purpose"), selection: $place.purpose) { ForEach(SavedPlacePurpose.allCases, id: \.self) { Text(t($0.rawValue)).tag($0) } }; TextField(t("address"), text: Binding(get: { place.addressText ?? "" }, set: { place.addressText = $0 })); TextField(t("instructions"), text: Binding(get: { place.findingInstructions ?? "" }, set: { place.findingInstructions = $0 }), axis: .vertical) }
                if let coordinate = place.coordinate { Section(t("pin")) { Text("\(coordinate.latitude), \(coordinate.longitude)").font(.caption); Button(t("directions")) { onDirections?(place); dismiss() }.disabled(onDirections == nil) } }
                if let error { Text(error).foregroundStyle(.red) }
                if model.savedPlaces.contains(where: { $0.id == place.id }) { Button(t("delete"), role: .destructive) { confirmingDelete = true } }
            }.navigationTitle(t("save"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(t("save")) { saving = true; place.updatedAt = Date(); Task { if await model.savePlace(place) { onSaved?(); dismiss() } else { error = t("saveError") }; saving = false } }.disabled(saving || place.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
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
