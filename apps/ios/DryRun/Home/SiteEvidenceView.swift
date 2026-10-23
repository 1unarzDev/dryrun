import SwiftUI
import DryRunCore

/// Location records: official planning evidence for this address (elevation, flood design level, wildfire rating,
/// hurricane evacuation zone), copied by the family with its source, then reviewed once before saving. Core decides
/// what each record can support (`SiteHazardContext`): unknown or mismatched datums are never compared, terrain is not
/// floor height, a community wildfire rating is not this home's risk, and a planning route is not an evacuation order.
/// Records stay encrypted on this phone; only that minimized status can enter an opted-in cloud context.
struct SiteEvidenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding: Kind?
    @State private var confirmingRemove = false

    enum Kind: String, CaseIterable, Identifiable { case elevation, flood, wildfire, hurricane; var id: String { rawValue } }

    var body: some View {
        let l = model.localizer
        List {
            if let household = model.household {
                let profile = household.siteHazards
                let context = SiteHazardContext(profile, jurisdictionID: household.regionID, at: Date(), locationBinding: SiteHazardBinding.of(household))
                Section { Text(l("site.intro")).font(.callout) }
                if household.regionID.isEmpty {
                    Section { Label(l("site.needsCounty"), systemImage: "map").foregroundStyle(Theme.caution) }
                }
                if let profile, profile.locationBinding != SiteHazardBinding.of(household) {
                    Section {
                        Label(l("site.otherAddress"), systemImage: "exclamationmark.triangle").foregroundStyle(Theme.caution)
                        Button(l("site.remove"), role: .destructive) { confirmingRemove = true }
                    }
                    .accessibilityIdentifier("site.otherAddress")
                }
                Section(l("site.status")) {
                    statusRow(l("site.kind.elevation"), value: l(context.elevationRecorded ? "site.recorded" : "site.notRecorded"))
                    statusRow(l("site.kind.flood"), value: l("site.flood.\(context.floodComparison)"))
                    statusRow(l("site.kind.wildfire"), value: context.wildfireRating.map { l("site.wildfire.rating", ["rating": l("site.wildfire.\($0)")]) } ?? l("site.notRecorded"))
                    statusRow(l("site.kind.hurricane"), value: l(context.hurricanePlan == "recordedOfficialPlanningRoute" ? "site.hurricane.recorded" : "site.notRecorded"))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("site.status")
                if let sources = profile?.sources, !sources.isEmpty {
                    Section(l("site.sources")) {
                        ForEach(sources, id: \.id) { source in
                            let usable = source.usable(at: Date(), jurisdictionID: household.regionID)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.publisher).font(.headline)
                                Text(l("site.sourceDates", ["retrieved": source.retrievedAt.formatted(date: .abbreviated, time: .omitted),
                                                            "until": source.validUntil.formatted(date: .abbreviated, time: .omitted)])).font(.caption)
                                Label(l(usable ? "site.sourceCounts" : "site.sourceDoesNotCount"), systemImage: usable ? "checkmark.seal" : "clock.badge.exclamationmark")
                                    .font(.caption).foregroundStyle(usable ? Theme.accent : Theme.caution)
                            }
                        }
                    }
                }
                Section(l("site.add")) {
                    ForEach(Kind.allCases) { kind in
                        Button { adding = kind } label: { Label(l("site.kind.\(kind.rawValue)"), systemImage: symbol(kind)) }
                            .accessibilityIdentifier("site.add.\(kind.rawValue)")
                    }
                }
                Section(l("site.limits")) {
                    ForEach(["terrain", "wildfire", "hurricane", "scope"], id: \.self) { Text(l("site.limit.\($0)")).font(.footnote) }
                }
                if profile != nil {
                    Section { Button(l("site.remove"), role: .destructive) { confirmingRemove = true }.accessibilityIdentifier("site.remove") }
                }
            }
        }
        .navigationTitle(l("site.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.scopeSessionID) { _, _ in dismiss() }
        .sheet(item: $adding) { kind in NavigationStack { SiteRecordEditor(kind: kind) } }
        .confirmationDialog(l("site.removeConfirm"), isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(l("site.remove"), role: .destructive) { Task { await model.updateSiteHazards(nil) } }
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)); Text(value).font(.callout) }
            .accessibilityElement(children: .combine)
    }

    private func symbol(_ kind: Kind) -> String {
        switch kind { case .elevation: "arrow.up.and.down"; case .flood: "water.waves"; case .wildfire: "flame"; case .hurricane: "hurricane" }
    }
}

/// One official record and its source, shown back to the family for review before it is saved.
struct SiteRecordEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: SiteEvidenceView.Kind
    @State private var publisher = ""
    @State private var url = "https://"
    @State private var retrieved = Date()
    @State private var validUntil = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var copiedFromOfficial = false
    @State private var value = ""
    @State private var uncertainty = ""
    @State private var feet = true
    @State private var datum = ""
    @State private var finishedFloor = false
    @State private var rating = "moderate"
    @State private var zone = ""
    @State private var route = ""
    @State private var reviewing = false
    @State private var failed = false
    @State private var datasetVersion: String?
    @State private var askingLookup = false
    @State private var lookingUp = false
    @State private var lookupNote: String?

    /// The saved address's coordinates, the only thing an official lookup sends.
    private var coordinate: (latitude: Double, longitude: Double)? {
        guard let location = model.household?.privateLocation, let lat = location.latitude, let lon = location.longitude else { return nil }
        return (lat, lon)
    }

    var body: some View {
        let l = model.localizer
        Form {
            if kind == .flood || kind == .elevation {
                Section(l("site.lookup.section")) {
                    Button(l(kind == .flood ? "site.lookup.flood" : "site.lookup.elevation")) { askingLookup = true }
                        .disabled(coordinate == nil || lookingUp)
                        .accessibilityIdentifier("site.lookup")
                    if coordinate == nil { Text(l("site.lookup.needsAddress")).font(.caption).foregroundStyle(.secondary) }
                    if lookingUp { ProgressView(l("site.lookup.working")) }
                    if let lookupNote { Text(lookupNote).font(.footnote).accessibilityIdentifier("site.lookupNote") }
                }
            }
            Section(l("site.kind.\(kind.rawValue)")) {
                switch kind {
                case .elevation, .flood:
                    TextField(l("site.value"), text: $value).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("site.value")
                    TextField(l("site.uncertainty"), text: $uncertainty).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("site.uncertainty")
                    Picker(l("site.units"), selection: $feet) { Text(l("site.feet")).tag(true); Text(l("site.meters")).tag(false) }.pickerStyle(.segmented)
                    TextField(l("site.datum"), text: $datum).accessibilityIdentifier("site.datum")
                    Text(l("site.datumHint")).font(.caption).foregroundStyle(.secondary)
                    if kind == .elevation {
                        Picker(l("site.surface"), selection: $finishedFloor) { Text(l("site.terrain")).tag(false); Text(l("site.finishedFloor")).tag(true) }
                    }
                case .wildfire:
                    Picker(l("site.kind.wildfire"), selection: $rating) {
                        ForEach(["veryLow", "low", "moderate", "high", "veryHigh"], id: \.self) { Text(l("site.wildfire.\($0)")).tag($0) }
                    }
                    Text(l("site.limit.wildfire")).font(.caption).foregroundStyle(.secondary)
                case .hurricane:
                    TextField(l("site.zone"), text: $zone).accessibilityIdentifier("site.zone")
                    TextField(l("site.route"), text: $route).accessibilityIdentifier("site.route")
                    Text(l("site.limit.hurricane")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(l("site.source")) {
                TextField(l("site.publisher"), text: $publisher).accessibilityIdentifier("site.publisher")
                TextField(l("site.url"), text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("site.url")
                DatePicker(l("site.retrieved"), selection: $retrieved, in: ...Date(), displayedComponents: .date)
                DatePicker(l("site.validUntil"), selection: $validUntil, in: retrieved..., displayedComponents: .date)
                Toggle(l("site.copied"), isOn: $copiedFromOfficial).accessibilityIdentifier("site.copied")
            }
            if let problem { Section { Text(problem).foregroundStyle(Theme.caution).font(.footnote) } }
            if failed { Section { Text(l("site.saveFailed")).foregroundStyle(Theme.caution) } }
        }
        .navigationTitle(l("site.add"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.currentKey) { _, _ in dismiss() }
        .onChange(of: model.scopeSessionID) { _, _ in dismiss() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(l("site.review")) { reviewing = true }.disabled(problem != nil).accessibilityIdentifier("site.reviewButton")
            }
        }
        .confirmationDialog(l("site.reviewTitle"), isPresented: $reviewing, titleVisibility: .visible) {
            Button(l("site.save")) { Task { failed = !(await save()); if !failed { dismiss() } } }.accessibilityIdentifier("site.save")
        } message: {
            Text(summary)
        }
        .confirmationDialog(l("site.lookup.consentTitle"), isPresented: $askingLookup, titleVisibility: .visible) {
            Button(l("site.lookup.send")) { Task { await lookup() } }.accessibilityIdentifier("site.lookupSend")
        } message: {
            Text(l(kind == .flood ? "site.lookup.consentFlood" : "site.lookup.consentElevation"))
        }
    }

    // MARK: Official lookup (explicit, consented; pre-fills the form for review, never saves)

    private func lookup() async {
        let l = model.localizer
        guard let coordinate else { return }
        let key = model.currentKey, scope = model.scopeSessionID
        lookingUp = true; lookupNote = nil
        defer { lookingUp = false }
        do {
            if kind == .flood {
                let data = try await fetch(OfficialSiteLookup.floodQueryURL(latitude: coordinate.latitude, longitude: coordinate.longitude))
                guard model.currentKey == key, model.scopeSessionID == scope, !Task.isCancelled else { return }
                switch try OfficialSiteLookup.parseFlood(data) {
                case .record(let record):
                    let zone = record.subtype.map { "\(record.zone) (\($0.lowercased()))" } ?? record.zone
                    var lines = [l("site.lookup.zone", ["zone": zone])]
                    if record.specialFloodHazardArea == true { lines.append(l("site.lookup.sfha")) }
                    if let bfe = record.baseFloodElevationFeet, let d = record.verticalDatum {
                        value = bfe.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)); feet = true; datum = d
                        uncertainty = ""; adoptSource(OfficialSiteLookup.femaPublisher, OfficialSiteLookup.femaSourceURL, version: record.studyID)
                        lines.append(l("site.lookup.bfeFilled"))
                    } else {
                        lines.append(l("site.lookup.noBFE"))
                    }
                    lookupNote = lines.joined(separator: " ")
                case .notMapped: lookupNote = l("site.lookup.notMapped")
                case .ambiguous: lookupNote = l("site.lookup.ambiguous")
                }
            } else {
                let data = try await fetch(OfficialSiteLookup.elevationQueryURL(latitude: coordinate.latitude, longitude: coordinate.longitude))
                guard model.currentKey == key, model.scopeSessionID == scope, !Task.isCancelled else { return }
                if let terrain = try OfficialSiteLookup.parseElevation(data) {
                    value = terrain.feet.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)); feet = true
                    finishedFloor = false; uncertainty = ""; datum = ""
                    adoptSource(OfficialSiteLookup.usgsPublisher, OfficialSiteLookup.usgsSourceURL, version: nil)
                    lookupNote = l("site.lookup.elevationFilled")
                } else {
                    lookupNote = l("site.lookup.noElevation")
                }
            }
        } catch {
            guard model.currentKey == key, model.scopeSessionID == scope else { return }
            lookupNote = l("site.lookup.failed")
        }
    }

    /// The family still confirms the record against the source; the "copied" toggle is never set for them.
    private func adoptSource(_ name: String, _ link: String, version: String?) {
        publisher = name; url = link; retrieved = Date(); datasetVersion = version
    }

    private func fetch(_ queryURL: URL) async throws -> Data {
        var request = URLRequest(url: queryURL)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OfficialSiteLookup.LookupError.serviceError }
        return data
    }

    // MARK: Validation and saving

    private var meters: Double? { Double(value.replacingOccurrences(of: ",", with: ".")).map { feet ? $0 * 0.3048 : $0 } }
    private var uncertaintyMeters: Double? { Double(uncertainty.replacingOccurrences(of: ",", with: ".")).map { feet ? $0 * 0.3048 : $0 } }

    /// The first reason this record cannot be saved, or nil. Unknown datum or uncertainty is never filled in.
    private var problem: String? {
        let l = model.localizer
        guard let household = model.household, !household.regionID.isEmpty else { return l("site.needsCounty") }
        guard !publisher.trimmingCharacters(in: .whitespaces).isEmpty, let link = URL(string: url), link.scheme == "https", link.host != nil else { return l("site.problem.source") }
        guard copiedFromOfficial else { return l("site.problem.copied") }
        switch kind {
        case .elevation, .flood:
            guard let m = meters, m.isFinite, let u = uncertaintyMeters, u.isFinite, u >= 0 else { return l("site.problem.number") }
            let d = datum.trimmingCharacters(in: .whitespaces)
            guard !d.isEmpty, d.lowercased() != "unknown" else { return l("site.problem.datum") }
        case .wildfire: break
        case .hurricane:
            guard !zone.trimmingCharacters(in: .whitespaces).isEmpty, !route.trimmingCharacters(in: .whitespaces).isEmpty else { return l("site.problem.zone") }
        }
        return nil
    }

    private var summary: String {
        let l = model.localizer
        let detail: String = switch kind {
        case .elevation, .flood: "\(value) \(l(feet ? "site.feet" : "site.meters")) ± \(uncertainty) · \(datum)"
        case .wildfire: l("site.wildfire.\(rating)")
        case .hurricane: "\(zone) · \(route)"
        }
        return l("site.reviewBody", ["record": l("site.kind.\(kind.rawValue)"), "detail": detail, "publisher": publisher])
    }

    private func save() async -> Bool {
        guard problem == nil, let household = model.household else { return false }
        var profile = household.siteHazards ?? SiteHazardProfile(jurisdictionID: household.regionID)
        // Records from another county or address are not mixed with this one.
        if profile.jurisdictionID != household.regionID || profile.locationBinding != SiteHazardBinding.of(household) {
            profile = SiteHazardProfile(jurisdictionID: household.regionID)
        }
        let sourceID = "src-\(kind.rawValue)-\(Int(retrieved.timeIntervalSince1970))"
        profile.sources.removeAll { $0.id == sourceID }
        var source = SiteHazardSource(id: sourceID, authority: .official, publisher: publisher.trimmingCharacters(in: .whitespaces),
                                      url: url.trimmingCharacters(in: .whitespaces), jurisdictionID: household.regionID,
                                      retrievedAt: retrieved, validUntil: validUntil, reviewed: true)
        source.datasetVersion = datasetVersion
        profile.sources.append(source)
        let d = datum.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .elevation:
            guard let m = meters, let u = uncertaintyMeters else { return false }
            profile.elevation = SiteElevation(meters: m, uncertaintyMeters: u, verticalDatum: d, surface: finishedFloor ? .finishedFloor : .terrain, sourceID: sourceID)
        case .flood:
            guard let m = meters, let u = uncertaintyMeters else { return false }
            profile.floodLevel = SiteFloodLevel(meters: m, uncertaintyMeters: u, verticalDatum: d, sourceID: sourceID)
        case .wildfire:
            profile.wildfire = SiteWildfireEvidence(rating: rating, scale: .community, sourceID: sourceID)
        case .hurricane:
            profile.hurricane = HurricaneEvacuationPlan(zone: zone.trimmingCharacters(in: .whitespaces),
                                                        routeIDs: [route.trimmingCharacters(in: .whitespaces)], sourceID: sourceID)
        }
        return await model.updateSiteHazards(profile)
    }
}
