import SwiftUI
import MapKit
import CoreLocation
import DryRunCore

/// Full-size native MapKit planning experience. The directory remains useful
/// as text when tiles, search, or directions are unavailable.
@MainActor
struct MapPlanningView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: RegionalResourcesStore
    @State private var camera: MapCameraPosition
    @State private var selectionID: String?
    @State private var selectedResource: PublicResource?
    @State private var selectedSearchResult: AppleMapSearchResult?
    @State private var showingSearch = false
    @State private var showingList = false
    @State private var category: ResourceServiceType?
    @State private var route: MapTravelPreview?
    @State private var isLoadingRoute = false
    @State private var routeMessage: String?
    @State private var routeGeneration = 0
    @State private var pendingDestination: GeographicCoordinate?
    @State private var showingRouteOptions = false
    @State private var travelMode: MapTravelMode = .walking
    @State private var saveDraft: SavePlaceDraft?
    @State private var locationService: OptionalLocationService
    private let searchService = AppleMapSearchService()
    private let directionsService = AppleMapDirectionsService()
    private let onSavePlace: ((GeographicCoordinate, String, String?) async -> Bool)?

    init(content: ContentLibrary, client: PublicAPIClient, regionID: String,
         onSavePlace: ((GeographicCoordinate, String, String?) async -> Bool)? = nil) {
        let resourceStore = RegionalResourcesStore(content: content, client: client, regionID: regionID)
        self.init(store: resourceStore, onSavePlace: onSavePlace)
    }

    init(store: RegionalResourcesStore,
         onSavePlace: ((GeographicCoordinate, String, String?) async -> Bool)? = nil) {
        _store = State(initialValue: store)
        _camera = State(initialValue: .region(store.hint().mapRegion))
        _locationService = State(initialValue: OptionalLocationService())
        self.onSavePlace = onSavePlace
    }

    private var visibleResources: [PublicResource] {
        guard let category else { return store.resources }
        return store.resources.filter { $0.serviceType == category }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                privacyBanner
                countyPicker
                Picker("View", selection: $showingList) {
                    Text("Map").tag(false)
                    Text("List").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                if showingList { listView } else { mapView }
            }
            .navigationTitle("Plan with maps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSearch = true } label: { Label("Search Apple Maps", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("map.search")
                }
            }
            .sheet(isPresented: $showingSearch) {
                MapSearchSheet(region: store.hint(), service: searchService) { result in
                    selectedSearchResult = result
                    selectionID = result.selectionID
                    route = nil
                    routeGeneration &+= 1
                    camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude),
                                                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
                }
            }
            .sheet(item: $selectedResource) { resource in
                ResourceDetailSheet(resource: resource, source: resource.sourceIDs.compactMap(store.source).first,
                                    coordinateSources: (resource.coordinateSourceIDs ?? []).compactMap(store.source),
                                    onPreview: { if let coordinate = resource.coordinate { beginPreview(coordinate) } },
                                    onSave: onSavePlace.map { _ in { coordinate in requestSave(coordinate, label: resource.name, address: resource.contact.address) } },
                                    openMaps: { openAppleMaps(name: resource.name, coordinate: $0) })
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedSearchResult) { result in
                SearchResultDetailSheet(result: result, onPreview: { beginPreview(result.coordinate) },
                                         onSave: onSavePlace.map { _ in { coordinate in requestSave(coordinate, label: result.name, address: result.address) } },
                                         openMaps: { openAppleMaps(name: result.name, coordinate: $0) })
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingRouteOptions) {
                if let destination = pendingDestination {
                    TravelOptionsSheet(mode: $travelMode,
                                       onUseCurrentLocation: { preview(destination, mode: travelMode); showingRouteOptions = false },
                                       onCancel: { showingRouteOptions = false })
                }
            }
            .sheet(item: $saveDraft) { draft in
                SavePlaceSheet(draft: draft, onSave: { label in
                    guard let onSavePlace else { return false }
                    return await onSavePlace(draft.coordinate, label, draft.address)
                }, onCancel: { saveDraft = nil })
            }
            .alert("Travel preview", isPresented: Binding(get: { routeMessage != nil }, set: { if !$0 { routeMessage = nil } })) {
                Button("OK", role: .cancel) { routeMessage = nil }
            } message: { Text(routeMessage ?? "") }
            .task { await store.refresh() }
            .onChange(of: store.selectedRegionID) { _, _ in
                route = nil
                routeGeneration &+= 1
                camera = .region(store.hint().mapRegion)
            }
        }
    }

    private var privacyBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Official directory plus Apple Maps search", systemImage: "map")
                .font(.subheadline.weight(.semibold))
            Text("Directory contacts are bundled or cached for offline use. Search and travel previews use Apple services and are planning aids, not verified evacuation routes or proof that a site is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private var countyPicker: some View {
        HStack {
            Picker("County", selection: Binding(get: { store.selectedRegionID }, set: { store.select(regionID: $0) })) {
                ForEach(store.regionIDs, id: \.self) { id in
                    Text(store.regionName(id)).tag(id)
                }
            }
            .labelsHidden()
            Spacer()
            Menu {
                Button("All categories") { category = nil }
                ForEach(ResourceServiceType.allCases, id: \.self) { type in
                    Button(type.mapLabel) { category = type }
                }
            } label: {
                Label(category?.mapLabel ?? "All categories", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.callout)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var listView: some View {
        List {
            if visibleResources.filter({ $0.coordinate != nil }).isEmpty {
                Section { Text("No mapped local resources yet. Statewide contacts remain available below.").foregroundStyle(.secondary) }
            }
            ForEach(visibleResources) { resource in
                Button { selectedResource = resource } label: {
                    ResourceListRow(resource: resource)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.resource.\(resource.id)")
            }
            Section {
                Label("Checked directory data stays useful offline. Apple Maps search is unavailable without a network connection.", systemImage: "wifi.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var mapView: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera, selection: $selectionID) {
                ForEach(visibleResources.compactMap(MapDirectoryMarker.init)) { marker in
                    Marker(marker.title, systemImage: "building.2", coordinate: marker.coordinate)
                        .tint(.blue)
                        .tag(marker.selectionID)
                }
                if let result = selectedSearchResult {
                    Marker(result.name, systemImage: "magnifyingglass", coordinate: CLLocationCoordinate2D(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude))
                        .tint(.orange)
                        .tag(result.selectionID)
                }
                if let route {
                    MapPolyline(coordinates: route.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.blue, lineWidth: 5)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
            .onChange(of: selectionID) { _, value in
                guard let value else { return }
                route = nil
                routeGeneration &+= 1
                if let id = value.split(separator: ":", maxSplits: 1).last,
                   let resource = store.resources.first(where: { $0.id == id }) {
                    selectedResource = resource
                }
            }
            .accessibilityLabel("Apple Maps regional planning map")
            if visibleResources.filter({ $0.coordinate != nil }).isEmpty {
                Text("No verified resource pins in this county. The map shows regional context; use the list for contacts.")
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
            if route != nil {
                routeBadge
                    .padding()
            }
        }
    }

    private var routeBadge: some View {
        HStack {
            Label("Planning preview", systemImage: "arrow.triangle.turn.up.right.diamond")
            Spacer()
            if let route { Text("\(route.distanceMeters / 1609.344, specifier: "%.1f") mi") }
            Button("Clear") { routeGeneration &+= 1; route = nil }
        }
        .font(.callout.weight(.semibold))
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func beginPreview(_ destination: GeographicCoordinate) {
        // Dismiss the detail sheet before presenting the origin/mode sheet. SwiftUI only presents one sheet at a
        // time from this view; leaving the selected item set would make the explicit preview action appear inert.
        selectedResource = nil
        selectedSearchResult = nil
        routeGeneration &+= 1
        route = nil
        pendingDestination = destination
        showingRouteOptions = true
    }

    private func requestSave(_ coordinate: GeographicCoordinate, label: String, address: String?) {
        guard onSavePlace != nil else { return }
        selectedResource = nil
        selectedSearchResult = nil
        saveDraft = SavePlaceDraft(coordinate: coordinate, suggestedLabel: label, address: address)
    }

    private func preview(_ destination: GeographicCoordinate, mode: MapTravelMode) {
        routeGeneration &+= 1
        let ticket = routeGeneration
        Task { @MainActor in
            isLoadingRoute = true
            defer { isLoadingRoute = false }
            let location = locationService.lastLocation ?? await locationService.requestOneShot()
            guard let location,
                  let origin = GeographicCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) else {
                guard ticket == routeGeneration else { return }
                routeMessage = "Location is unavailable. Enable When In Use access in Settings or open the destination in Apple Maps."
                return
            }
            do {
                let preview = try await directionsService.preview(from: origin, to: destination, mode: mode)
                guard ticket == routeGeneration else { return }
                route = preview
                camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude), span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            } catch {
                guard ticket == routeGeneration else { return }
                routeMessage = "Apple Maps could not provide a \(mode.title.lowercased()) preview. Try another mode in Apple Maps."
            }
        }
    }

    private func openAppleMaps(name: String, coordinate: GeographicCoordinate) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)))
        item.name = name
        item.openInMaps(launchOptions: nil)
    }
}

private struct MapDirectoryMarker: Identifiable {
    let resource: PublicResource
    let coordinate: CLLocationCoordinate2D
    var id: String { resource.id }
    var selectionID: String { MapSelectionID.directory(resource.id) }
    var title: String { resource.name }
    init?(resource: PublicResource) {
        guard let coordinate = resource.coordinate else { return nil }
        self.resource = resource
        self.coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

private extension PublicResource {
    var coordinate: GeographicCoordinate? {
        guard let latitude, let longitude else { return nil }
        return GeographicCoordinate(latitude: latitude, longitude: longitude)
    }
}

private extension ResourceServiceType {
    var mapLabel: String {
        switch self {
        case .emergencyManagement: "Emergency management"; case .publicHealth: "Public health"; case .waterProvider: "Water"; case .electricUtility: "Electricity"; case .transportation: "Transportation"; case .assistanceLine: "Help lines"; case .assistanceRegistry: "Assistance registry"; case .disasterAssistance: "Disaster assistance"; case .warmingCenter: "Warming"; case .coolingCenter: "Cooling"; case .shelter: "Shelters"; case .alertEnrollment: "Alert sign-up"; case .other: "Other"
        }
    }
}

private extension ActivationState {
    var mapLabel: String {
        switch self {
        case .active: "reported active (time-limited)"
        case .inactive: "reported inactive"
        case .unknown: "unknown"
        case .notApplicable: "not applicable"
        }
    }
}

private struct ResourceListRow: View {
    let resource: PublicResource
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: resource.coordinate == nil ? "text.book.closed" : "mappin.and.ellipse")
                .foregroundStyle(resource.coordinate == nil ? .secondary : .blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(resource.name).font(.body.weight(.semibold))
                Text(resource.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                if let address = resource.contact.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                Text(resource.coordinate == nil ? "Directory contact · list only" : "Mapped office · source checked \(resource.coordinateCheckedAt ?? resource.checkedAt)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ResourceDetailSheet: View {
    let resource: PublicResource
    let source: SourceRef?
    let coordinateSources: [SourceRef]
    let onPreview: () -> Void
    let onSave: ((GeographicCoordinate) -> Void)?
    let openMaps: (GeographicCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(resource.name).font(.title3.weight(.semibold))
                    Text(resource.summary)
                    Text(resource.serviceType.mapLabel).font(.callout).foregroundStyle(.secondary)
                }
                if let address = resource.contact.address { Section("Address") { Text(address) } }
                if let phone = resource.contact.phone {
                    Section("Contact") {
                        if let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                            Link(destination: url) { Label(phone, systemImage: "phone") }
                        } else { Text(phone).textSelection(.enabled) }
                        if let site = resource.contact.url, let url = URL(string: site) {
                            Link(destination: url) { Label("Open official site", systemImage: "safari") }
                        }
                    }
                } else if let site = resource.contact.url, let url = URL(string: site) {
                    Section("Contact") { Link("Open official site", destination: url) }
                }
                Section("Source") {
                    Text(source?.publisher ?? resource.publisher)
                    if let source, let url = URL(string: source.url) {
                        Link("Open directory source", destination: url)
                    }
                    Text("Directory checked \(resource.checkedAt)").font(.caption).foregroundStyle(.secondary)
                    if let coordinateCheckedAt = resource.coordinateCheckedAt {
                        Text("Coordinate checked \(coordinateCheckedAt)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Activation: \(resource.activation.mapLabel)").font(.caption).foregroundStyle(.secondary)
                    if !coordinateSources.isEmpty {
                        Text("Map coordinate: \(coordinateSources.map(\.publisher).joined(separator: ", "))")
                            .font(.caption)
                        ForEach(coordinateSources) { coordinateSource in
                            if let url = URL(string: coordinateSource.url) {
                                Link("Open map coordinate source", destination: url)
                            }
                        }
                    }
                    Text("A map pin does not confirm activation, capacity, accessibility, or safe arrival.").font(.footnote).foregroundStyle(.secondary)
                }
                if let coordinate = resource.coordinate {
                    Section {
                        Button("Preview ordinary walking route") { onPreview() }
                        Button("Open in Apple Maps") { openMaps(coordinate) }
                        if let onSave { Button("Save as a private planning place") { onSave(coordinate) } }
                    }
                }
            }
            .navigationTitle("Directory place")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

}

private struct SearchResultDetailSheet: View {
    let result: AppleMapSearchResult
    let onPreview: () -> Void
    let onSave: ((GeographicCoordinate) -> Void)?
    let openMaps: (GeographicCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text(result.name).font(.title3.weight(.semibold)); Text("Apple Maps search result — not an official Dry Run resource.").foregroundStyle(.secondary) }
                if let address = result.address { Section("Address") { Text(address) } }
                Section {
                    Button("Preview ordinary walking route") { onPreview() }
                    Button("Open in Apple Maps") { openMaps(result.coordinate) }
                    if let onSave { Button("Save as a private planning place") { onSave(result.coordinate) } }
                }
                Section { Text("Search and travel previews use Apple services. A result does not prove a site is open, safe, or accessible.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Apple Maps result")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct TravelOptionsSheet: View {
    @Binding var mode: MapTravelMode
    let onUseCurrentLocation: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose an origin and transport mode before asking Apple Maps for a route. Dry Run never assumes that a car is available.")
                        .font(.callout)
                }
                Section("Origin") {
                    Button("Use my current location") { onUseCurrentLocation() }
                    Text("Location access is optional and requested only after this action.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Transport") {
                    Picker("Mode", selection: $mode) {
                        ForEach(MapTravelMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("Planning route — road and emergency conditions may differ. This is not an evacuation or accessibility certification.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Travel preview")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
        }
    }
}

private struct SavePlaceDraft: Identifiable {
    let id = UUID()
    let coordinate: GeographicCoordinate
    let suggestedLabel: String
    let address: String?
}

private struct SavePlaceSheet: View {
    let draft: SavePlaceDraft
    let onSave: (String) async -> Bool
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var isSaving = false
    @State private var error: String?

    init(draft: SavePlaceDraft, onSave: @escaping (String) async -> Bool, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        _label = State(initialValue: draft.suggestedLabel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Private planning place") {
                    TextField("Label", text: $label)
                    if let address = draft.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
                Section {
                    Text("This point is encrypted in Dry Run's private vault. It is a planning annotation and does not prove an outdoor route is safe.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Save place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        isSaving = true
                        error = nil
                        Task { @MainActor in
                            let saved = await onSave(cleaned)
                            isSaving = false
                            if saved { dismiss() }
                            else { error = "The private save failed. Your draft is still here; try again." }
                        }
                    }
                    .disabled(isSaving || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

@MainActor
private struct MapSearchSheet: View {
    let region: MapRegionHint
    let service: AppleMapSearchService
    let onSelect: (AppleMapSearchResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [AppleMapSearchResult] = []
    @State private var error: String?
    @State private var isSearching = false
    @State private var generation = 0
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Queries go to Apple Maps. Dry Run does not send search text to its public service.").font(.footnote).foregroundStyle(.secondary) }
                Section {
                    TextField("Search a place", text: $query)
                        .textInputAutocapitalization(.words)
                        .onSubmit { search() }
                    Button { search() } label: { Label(isSearching ? "Searching…" : "Search Apple Maps", systemImage: "magnifyingglass") }.disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
                Section("Apple Maps results") {
                    ForEach(results) { result in
                        Button { onSelect(result); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 3) { Text(result.name).font(.body.weight(.semibold)); if let address = result.address { Text(address).font(.caption).foregroundStyle(.secondary) } }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Search Apple Maps")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { service.cancel(); dismiss() } } }
        }
    }
    private func search() {
        generation &+= 1
        let ticket = generation
        Task { @MainActor in
            isSearching = true; error = nil
            defer { isSearching = false }
            do {
                let found = try await service.search(query: query, region: region)
                guard ticket == generation else { return }
                results = found
            }
            catch is CancellationError { }
            catch { guard ticket == generation else { return }; error = "Apple Maps search is unavailable right now. Directory contacts remain available." }
        }
    }
}
