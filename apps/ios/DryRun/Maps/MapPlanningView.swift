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
    @State private var contextualSaveFinished = false
    @State private var deferredDestination: MapPlanningDestination?
    private let initialPurpose: SavedPlacePurpose?
    private let dismissAfterSave: Bool
    /// False when pushed onto an existing navigation stack (a preparation task), so stacks never nest.
    private let embedInNavigation: Bool
    private let planningContext: MapPlanningContext
    private let plannedExteriorHandoff: PlannedExteriorHandoff?
    @State private var showingSearch = false
    @State private var showingList = false
    @State private var discovery = NearbyDiscovery()
    /// Places for the household's open preparation tasks (offline plans; listings stay on this phone).
    @State private var taskSearch = TaskResourceSearch()
    @State private var taskPlanRefresh: Task<Void, Never>?
    /// Whether the listed task results were searched with Gemini's accepted plans (not merely whether plans arrived).
    @State private var listFromGemini = false
    @State private var routeRequest = MapRoutePreviewModel()
    @State private var routeEndpoints: MapPlanningRouteEndpoints?
    @State private var mode: MapTravelMode = .walking
    @State private var originID = "home"
    @State private var message: String?
    @State private var radius = 5000.0
    @State private var location = OptionalLocationService()
    @State private var originResolver = HomeOriginResolver()

    init(content: ContentLibrary, client: PublicAPIClient, regionID: String,
         purpose: SavedPlacePurpose? = nil, dismissAfterSave: Bool = false, embedInNavigation: Bool = true,
         context: MapPlanningContext = MapPlanningContext(), plannedExteriorHandoff: PlannedExteriorHandoff? = nil) {
        _store = State(initialValue: RegionalResourcesStore(content: content, client: client, regionID: regionID))
        initialPurpose = purpose; self.dismissAfterSave = dismissAfterSave; self.embedInNavigation = embedInNavigation
        planningContext = context; self.plannedExteriorHandoff = plannedExteriorHandoff
    }
    init(store: RegionalResourcesStore, purpose: SavedPlacePurpose? = nil, dismissAfterSave: Bool = false, embedInNavigation: Bool = true,
         context: MapPlanningContext = MapPlanningContext(), plannedExteriorHandoff: PlannedExteriorHandoff? = nil) {
        _store = State(initialValue: store)
        initialPurpose = purpose; self.dismissAfterSave = dismissAfterSave; self.embedInNavigation = embedInNavigation
        planningContext = context; self.plannedExteriorHandoff = plannedExteriorHandoff
    }
    /// Choosing a meeting place is the task itself: a tapped result goes straight to its editor.
    private var choosingMeetup: Bool { initialPurpose == .outsideMeetingPoint || initialPurpose == .backupMeetingPlace }
    private var places: [SavedPlace] { model.savedPlaces.filter { $0.homeID == model.household?.stableHomeID } }
    private var officialResources: [PublicResource] { store.resources(for: model.household?.regionID ?? "") }
    private var route: MapTravelPreview? { routeRequest.result?.preview }
    private var planningScope: MapPlanningScope? {
        model.household.map { MapPlanningScope(householdID: $0.id, homeID: $0.stableHomeID,
                                               isExample: $0.isFictional, homeCoordinate: homeCoordinate, sessionID: model.scopeSessionID) }
    }
    private struct DiscoveryScope: Hashable {
        var household: MapPlanningScope?
        var queries: [String]
    }
    private var discoveryScope: DiscoveryScope {
        .init(household: planningScope, queries: MapDiscoveryNeeds.queries(for: model.household))
    }
    private var originKey: HomeOriginResolver.Key? { HomeOriginResolver.key(model.household, sessionID: model.scopeSessionID) }
    /// Saved pin, or the saved address placed by Apple for this session when its candidates agree.
    private var homeCoordinate: GeographicCoordinate? { originResolver.coordinate(for: originKey) }
    private var hint: MapRegionHint? { (cameraCenter ?? homeCoordinate).map { MapRegionHint(center: $0, spanLatitude: radius / 55000, spanLongitude: radius / 55000) } }
    private func t(_ key: String) -> String { model.localizer("map.\(key)") }
    private func planningText(_ key: String) -> String { MapPlanningCopy.text(key, locale: model.locale) }
    private var hurricanePlanning: HurricanePlanningAvailability {
        guard let household = model.household else { return .notRecorded }
        return MapPlanningPolicy.hurricanePlanning(household: household, places: places,
            approvedSourceURLs: store.reviewedPlanningSourceURLs(for: household.regionID), at: Date())
    }
    private var currentHandoff: PlannedExteriorHandoff? {
        guard let handoff = plannedExteriorHandoff, let home = model.home, let household = model.household,
              handoff.isCurrent(home: home, household: household, places: places) else { return nil }
        return handoff
    }
    private var hasPlanningContext: Bool { planningContext.intent != .ordinary || planningContext.phase != .advance || hurricanePlanning != .notRecorded }
    private var planningObjectiveKey: String {
        if planningContext.phase == .advance && (planningContext.intent == .tornadoShelter || planningContext.intent == .structureFire) {
            return planningContext.intent.rawValue + "Advance"
        }
        return planningContext.intent.rawValue
    }
    private var planningSummary: String {
        if planningContext.intent == .ordinary {
            switch hurricanePlanning {
            case .available(let plan): return planningText("zone") + ": " + plan.zone
            case .needsReview: return planningText("hurricaneReview")
            case .notRecorded: break
            }
        }
        return planningText(planningObjectiveKey)
    }

    var body: some View {
        if embedInNavigation { NavigationStack { content } } else { content }
    }

    private var content: some View {
            VStack(spacing: 0) {
                if let initialPurpose, choosingMeetup {
                    Label(t(initialPurpose.rawValue), systemImage: initialPurpose.mapSymbol)
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 8)
                }
                // A safety qualifier: it must wrap, never truncate, even when the map below claims the height (PLAN-06,
                // es at AX). Vertical fixedSize keeps its full height inside this VStack.
                Text(t("privacy")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                HomeOriginStatusView(resolver: originResolver, key: originKey).padding(.horizontal).padding(.bottom, 6)
                if hasPlanningContext {
                    HStack(alignment: .top) {
                        Text(planningSummary).font(.caption).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(planningText("details")) { showingList = true }.font(.caption.weight(.semibold))
                    }.padding(.horizontal).padding(.bottom, 8)
                }
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
                    VStack(alignment: .leading, spacing: 4) {
                      HStack {
                        Text(model.localizer("map.routeSummary", ["mode": t(route.mode.rawValue), "distance": distance(route.distanceMeters), "duration": PlanningMeasurements.duration(seconds: route.expectedTravelTime, localizer: model.localizer)]))
                        Spacer(); Button(t("clear")) { routeRequest.cancel(clearPreview: true) }
                      }
                      Text(t("routeNote")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.caption).padding(10)
                }
                if let message { Text(message).font(.caption).padding(10) }
            }
            .navigationTitle(t("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if embedInNavigation {
                    ToolbarItem(placement: .cancellationAction) { Button(t("done")) { dismiss() }.accessibilityIdentifier("map.done") }
                }
                ToolbarItem(placement: .primaryAction) { Button { showingSearch = true } label: { Label(t("search"), systemImage: "magnifyingglass") }.accessibilityIdentifier("map.search") }
            }
            .sheet(isPresented: $showingSearch, onDismiss: { if let pendingSearchResult { select(pendingSearchResult); self.pendingSearchResult = nil } }) {
                MapSearchSheet(region: hint, onSelect: { pendingSearchResult = $0; showingSearch = false })
            }
            .sheet(item: $selected, onDismiss: { if let deferredPlace { editedPlace = deferredPlace; self.deferredPlace = nil } }) { result in destinationSheet(result) }
            // Presented from the place itself: a separate flag could show the sheet before the place was set (blank sheet).
            .sheet(item: $editedPlace, onDismiss: {
                if contextualSaveFinished && dismissAfterSave { contextualSaveFinished = false; dismiss() }
                else if let deferredDestination { selected = deferredDestination; self.deferredDestination = nil }
            }) { place in
                PlaceEditorView(place: place, onSaved: { contextualSaveFinished = true }, onDirections: { place in
                    guard place.coordinate != nil else { return }
                    deferredDestination = MapPlanningDestination(place: place)
                })
            }
            .task(id: discoveryScope) {
                resetPlanningSession()
                if let homeCoordinate, planningContext.allowsOrdinaryDirections {
                    let newHomeRegion = MapRegionHint(center: homeCoordinate, spanLatitude: radius / 55000, spanLongitude: radius / 55000)
                    camera = .region(newHomeRegion.mapRegion)
                    async let general: Void = discovery.search(region: newHomeRegion, locale: model.locale, queries: discoveryScope.queries)
                    await refreshTaskSuggestions(home: homeCoordinate, scope: planningScope)
                    await general
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
            .task(id: originKey) { await originResolver.resolve(originKey) }
            .onDisappear { discovery.cancel(); taskPlanRefresh?.cancel(); taskSearch.cancel(); routeRequest.cancel(); originResolver.cancel() }
            .onChange(of: model.cloudResourcesEnabled) { _, _ in
                guard let homeCoordinate, !choosingMeetup else { return }
                taskPlanRefresh?.cancel()
                let scope = planningScope
                taskPlanRefresh = Task {
                    await refreshTaskSuggestions(home: homeCoordinate, scope: scope)
                }
            }
    }

    private var map: some View {
        Map(position: $camera) {
            if let homeCoordinate { Marker(t("home"), systemImage: "house.fill", coordinate: homeCoordinate.cl).tint(.indigo) }
            ForEach(places) { place in
                if let coordinate = place.coordinate {
                    Annotation(place.label, coordinate: coordinate.cl) {
                        Button { editedPlace = place } label: { Image(systemName: place.purpose.mapSymbol).font(.title).foregroundStyle(place.purpose.mapColor).background(.background, in: Circle()) }
                            .accessibilityLabel(place.label)
                    }
                }
            }
            ForEach(discovery.results) { result in
                Annotation(result.name, coordinate: result.coordinate.cl) { Button { select(result) } label: { Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.orange).background(.background, in: Circle()) }.accessibilityLabel(result.name) }
            }
            ForEach(taskSearch.suggestions) { suggestion in
                if let coordinate = suggestion.coordinate {
                    Annotation(suggestion.name, coordinate: coordinate.cl) {
                        Button { select(suggestion) } label: {
                            Image(systemName: "checklist").font(.title3).foregroundStyle(.white).padding(6).background(.purple, in: Circle())
                        }
                        .accessibilityLabel(model.localizer("map.forTaskMarker", ["name": suggestion.name, "purpose": text(suggestion.purpose)]))
                    }
                }
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
            if hasPlanningContext { planningDetails }
            if let address = model.household?.privateLocation?.addressLine { Section(t("home")) { Text(address) } }
            if !choosingMeetup { meetupsSection }
            Section(t("saved")) {
                ForEach(places) { place in
                    Button { editedPlace = place } label: {
                        VStack(alignment: .leading) { Text(place.label).font(.headline); Text(t(place.purpose.rawValue)).font(.caption); if let address = place.addressText { Text(address) }; if let instructions = place.findingInstructions { Text(instructions) } }
                    }.buttonStyle(.plain)
                }
                Button(t("textPlace")) { newPlace(coordinate: nil) }.accessibilityIdentifier("map.addText")
            }
            if !choosingMeetup {
                Section {
                    if taskSearch.suggestions.isEmpty {
                        Text(taskSearch.isLoading ? t("searching") : t(model.resourcePlans.isEmpty ? "forTasksNone" : "forTasksEmpty")).foregroundStyle(.secondary)
                    }
                    ForEach(taskSearch.suggestions) { suggestion in
                        Button { select(suggestion) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name).font(.headline)
                                Text(text(suggestion.purpose)).font(.caption)
                                if let task = model.preparationTitle(taskID: suggestion.taskID) {
                                    Label(task, systemImage: "checklist").font(.caption2).foregroundStyle(.secondary)
                                }
                                if let homeCoordinate, let coordinate = suggestion.coordinate {
                                    Text(distance(homeCoordinate.clLocation.distance(from: coordinate.clLocation))).font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("map.forTask.\(suggestion.category)")
                    }
                } header: {
                    Text(t("forTasks"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("forTasksFooter"))
                        if model.cloudDirectorAvailable {
                            Toggle(t("geminiPlans"), isOn: Bindable(model).cloudResourcesEnabled)
                                .accessibilityIdentifier("map.geminiPlans")
                            Text(t("geminiPlansDetail")).font(.caption2)
                        }
                        Label(t(listFromGemini ? "plannedByGemini" : "plannedOnPhone"),
                              systemImage: listFromGemini ? "sparkles" : "iphone")
                            .accessibilityIdentifier("map.planSource")
                        if let note = model.resourcePlanNote { Text(note).foregroundStyle(Theme.caution) }
                    }
                }
            }
            Section(t("suggestions")) {
                if discovery.results.isEmpty { Text(discovery.isLoading ? t("searching") : t("empty")).foregroundStyle(.secondary) }
                ForEach(discovery.results) { result in
                    Button { select(result) } label: { VStack(alignment: .leading) {
                        Text(result.name).font(.headline)
                        Text(t(result.category == "hardware store" ? "hardware" : ["hospital", "pharmacy", "grocery"].contains(result.category ?? "") ? result.category! : "suggestion"))
                        if result.category == "hardware store" { Text(t("hardwarePlanningNote")).font(.caption).foregroundStyle(.secondary) }
                        if let address = result.address { Text(address).font(.caption) }
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

    /// Contextual meeting purposes reuse saved meetups and the out-of-area contact; no separate reconnection flow.
    @ViewBuilder private var meetupsSection: some View {
        if let household = model.household {
            let needs = MeetingPlanPolicy.needs(context: planningContext, household: household, places: places)
            Section {
                ForEach(needs, id: \.purpose) { need in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(planningText("meet.\(need.purpose.rawValue)")).font(.subheadline.weight(.semibold))
                            if need.isPrimary { Spacer(); Text(planningText("meet.primary")).font(.caption2).foregroundStyle(Theme.accent) }
                        }
                        switch need.status {
                        case .place(let id):
                            if let place = places.first(where: { $0.id == id }) {
                                Button(place.label) { editedPlace = place }.font(.callout)
                                if let instructions = place.findingInstructions { Text(instructions).font(.caption).foregroundStyle(.secondary) }
                            }
                        case .contact(let id):
                            if let contact = household.contacts.first(where: { $0.id == id }) {
                                if let url = contact.telephoneURL {
                                    Link(destination: url) { Label("\(contact.alias) · \(contact.phone ?? "")", systemImage: "phone") }.font(.callout)
                                } else { Text(contact.alias).font(.callout) }
                            }
                        case .missing:
                            if let purpose = MeetingPlanPolicy.savedPurpose(need.purpose) {
                                HStack {
                                    Text(planningText("meet.missingPlace")).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(planningText("meet.choose")) { newPlace(coordinate: nil, purpose: purpose) }.font(.caption.weight(.semibold))
                                }
                            } else { Text(planningText("meet.missingContact")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .accessibilityIdentifier("map.meetup.\(need.purpose.rawValue)")
                }
            } header: { Text(planningText("meetups")) } footer: {
                switch planningContext.intent {
                case .tornadoShelter: Text(planningText("meet.shelterFirst"))
                case .freezeContinuity, .heatContinuity, .waterContinuity: Text(planningText("meet.stayHome"))
                default: EmptyView()
                }
            }
        }
    }

    @ViewBuilder private var planningDetails: some View {
        Section(planningText("details")) {
            Text(planningText(planningObjectiveKey)).font(.callout)
            if planningContext.phase == .simulation { Text(planningText("simulation")).font(.caption.weight(.semibold)) }
            if planningContext.intent == .structureFire || planningContext.intent == .flashFlood {
                if let handoff = currentHandoff, let home = model.home {
                    Text(planningText("plannedExit") + ": " + HomeScenePresentation.routeElementLabel(handoff.exitPortalID, in: home, localizer: model.localizer))
                        .font(.callout)
                    if let meeting = places.first(where: { $0.id == handoff.meetingPlaceID }) {
                        Text(meeting.label).font(.headline)
                        if let instructions = meeting.findingInstructions { Text(instructions).font(.callout) }
                    } else { Text(planningText("missingGathering")).font(.callout) }
                    Text(planningText("homeMarker")).font(.caption).foregroundStyle(.secondary)
                } else { Text(planningText("reviewExit")).font(.callout) }
            }
            switch hurricanePlanning {
            case .notRecorded:
                if planningContext.intent == .hurricaneAdvance { Text(planningText("hurricaneUnknown")).font(.callout) }
            case .needsReview:
                Text(planningText("hurricaneReview")).font(.callout)
            case .available(let plan):
                Text(planningText("officialPlan")).font(.headline)
                Text(planningText("zone") + ": " + plan.zone)
                Text(plan.routeIDs.joined(separator: ", ")).font(.caption)
                if !plan.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(plan.instructions).font(.callout) }
                if let url = URL(string: plan.source.url) { Link(plan.source.publisher, destination: url) }
                Text(plan.source.retrievedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                if let destination = places.first(where: { $0.id == plan.destinationPlaceID }) {
                    Button(destination.label) { selected = MapPlanningDestination(place: destination) }
                }
                Text(planningText("officialBoundary")).font(.caption).foregroundStyle(.secondary)
                if model.household.map({ HouseholdContextSnapshot($0).transport }) == "noCar" {
                    Text(planningText("noCar")).font(.callout)
                } else { Text(planningText("confirmTransport")).font(.caption) }
            }
        }
    }

    private func destinationSheet(_ result: MapPlanningDestination) -> some View {
        let place = result.place
        return NavigationStack {
            Form {
                if let suggestion = result.suggestion { suggestionSection(suggestion) }
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
                if place.coordinate != nil && planningContext.allowsOrdinaryDirections {
                    Section(t("directions")) {
                        Picker(t("origin"), selection: $originID) {
                            if homeCoordinate != nil { Text(t("home")).tag("home") }
                            ForEach(places.filter { $0.coordinate != nil }) { Text($0.label).tag($0.id) }
                            Text(t("current")).tag("current")
                        }
                        Picker(t("mode"), selection: $mode) { ForEach(travelModes) { Text(t($0.rawValue)).tag($0) } }
                        Button(t("preview")) { preview(result) }.disabled(routeRequest.isLoading)
                        if let key = routeRequest.errorKey { Text(t(key)).font(.caption).foregroundStyle(.secondary) }
                        Text(t("routeNote")).font(.caption)
                    }
                } else { Section { Text(planningContext.allowsOrdinaryDirections ? t("noCoordinateDirections") : planningText(planningContext.intent.rawValue)).font(.caption) } }
                Section {
                    Button(t("save")) { deferredPlace = place; selected = nil }
                    if let coordinate = place.coordinate, planningContext.allowsOrdinaryDirections {
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
        if choosingMeetup { editedPlace = place } else { selected = MapPlanningDestination(place: place) }
    }
    /// No driving option is offered to a household that has recorded it has no car.
    private var travelModes: [MapTravelMode] {
        model.household.map { HouseholdContextSnapshot($0).transport } == "noCar" ? MapTravelMode.allCases.filter { $0 != .driving } : MapTravelMode.allCases
    }

    /// Offline plan text is a localization key; Gemini plan text is shown as written.
    private func text(_ keyOrText: String) -> String {
        model.localizer.has(keyOrText, in: "en") ? model.localizer(keyOrText) : keyOrText
    }

    @ViewBuilder private func suggestionSection(_ suggestion: ResourceSuggestion) -> some View {
        Section(t("forTask")) {
            Text(text(suggestion.purpose)).font(.callout)
            if let task = model.preparationTitle(taskID: suggestion.taskID) {
                Label(model.localizer("map.forTaskTask", ["task": task]), systemImage: "checklist").font(.caption)
            }
            if !suggestion.unknowns.isEmpty {
                Text(model.localizer("map.notVerified", ["items": suggestion.unknowns.map(text).joined(separator: "; ")])).font(.caption)
            }
            ForEach(suggestion.requiredEvidence, id: \.self) { Label(text($0), systemImage: "phone.arrow.up.right").font(.caption) }
            if let household = model.household {
                let access = OrdinaryAccess.of(destination: suggestion.coordinate, origin: homeCoordinate, household: household)
                if let meters = access.straightLineMeters {
                    Text(planningText("access.distance").replacingOccurrences(of: "{distance}", with: distance(meters))).font(.caption)
                }
                if access.withinOrdinaryRange == false { Text(planningText("access.beyond")).font(.caption) }
                else if !access.plannableModes.contains("driving") { Text(planningText("access.noCar")).font(.caption) }
            }
            let boundary = "resource.boundary.\(suggestion.category)"
            if model.localizer.has(boundary, in: "en") { Text(model.localizer(boundary)).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityIdentifier("map.suggestionDetail")
    }

    private func select(_ suggestion: ResourceSuggestion) {
        guard let household = model.household else { return }
        if let official = suggestion.official {
            let place = SavedPlace.officialResource(official, homeID: household.stableHomeID, purpose: .fallbackDestination)
            selected = MapPlanningDestination(place: place, officialResource: official, suggestion: suggestion)
        } else if let result = suggestion.result {
            let place = SavedPlace.appleSuggestion(sourceID: result.id, name: result.name, coordinate: result.coordinate,
                address: result.address, phone: result.phone, website: result.website, homeID: household.stableHomeID, purpose: .fallbackDestination)
            selected = MapPlanningDestination(place: place, suggestion: suggestion)
        }
        if suggestion.travelMode == "walking" || suggestion.travelMode == "transit" { mode = suggestion.travelMode == "transit" ? .transit : .walking }
    }

    private func select(_ resource: PublicResource) {
        guard let household = model.household else { return }
        let place = SavedPlace.officialResource(resource, homeID: household.stableHomeID, purpose: initialPurpose ?? .fallbackDestination)
        if choosingMeetup { editedPlace = place } else { selected = MapPlanningDestination(place: place, officialResource: resource) }
    }
    private func discover() async {
        guard discovery.enabled, let hint else { message = t("noHome"); return }
        await discovery.search(region: hint, locale: model.locale, queries: discoveryScope.queries)
    }
    /// Clear private drafts as well as public results before starting another household's search.
    /// Generation-based cancellation in both services rejects callbacks from the old scope.
    private func resetPlanningSession() {
        discovery.cancel(clearResults: true)
        taskPlanRefresh?.cancel()
        taskSearch.cancel(clearResults: true)
        listFromGemini = false
        routeRequest.cancel(clearPreview: true)
        routeEndpoints = nil
        pendingSearchResult = nil
        deferredPlace = nil
        deferredDestination = nil
        contextualSaveFinished = false
        selected = nil
        editedPlace = nil
        showingSearch = false
        message = nil
        originID = "home"
        mode = .walking
        cameraCenter = nil
    }

    private func refreshTaskSuggestions(home: GeographicCoordinate, scope: MapPlanningScope?) async {
        guard !choosingMeetup, planningContext.allowsOrdinaryDirections else { return }
        await model.refreshCloudResourcePlans()
        guard !Task.isCancelled, scope == planningScope else { return }
        let fromGemini = model.resourcePlansFromGemini
        await taskSearch.search(plans: model.activeResourcePlans, home: home, official: officialResources)
        guard !Task.isCancelled, scope == planningScope else { return }
        listFromGemini = fromGemini
    }
    private func distance(_ meters: Double) -> String {
        PlanningMeasurements.distance(meters: meters, countryCode: model.household?.privateLocation?.countryCode, localizer: model.localizer)
    }
    private func newPlace(coordinate: GeographicCoordinate?, label: String = "", address: String? = nil, provenance: SavedPlaceProvenance = .userSelected,
                          purpose: SavedPlacePurpose? = nil) {
        guard let household = model.household else { return }
        let place = SavedPlace(homeID: household.stableHomeID, purpose: purpose ?? initialPurpose ?? .fallbackDestination, label: label, coordinate: coordinate, addressText: address, provenance: provenance)
        if selected != nil { deferredPlace = place; selected = nil }
        else { editedPlace = place }
    }
    private func preview(_ destination: MapPlanningDestination) {
        guard planningContext.allowsOrdinaryDirections, let coordinate = destination.place.coordinate else { return }
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
