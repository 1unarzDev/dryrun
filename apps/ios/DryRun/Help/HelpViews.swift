import SwiftUI
import MapKit
import DryRunCore

/// Official directory. Works offline from the bundled/cached pack; the map is optional and needs tiles.
/// Phone and website actions always require a tap. Nothing auto-calls, and nothing private is sent.
struct HelpTabView: View {
    @Environment(AppModel.self) private var model
    @State private var showMapPlanner = false
    @State private var showCard = false

    var body: some View {
        let l = model.localizer
        let regionID = model.household?.regionID ?? ""
        let resources = model.regionalResources?.resources(for: regionID)
            ?? model.content?.resources(forRegion: regionID) ?? []
        let region = model.regionalResources?.regionInfo(for: regionID)
            ?? model.content?.region(regionID)
        List {
            Section {
                // A number shown as text with an explicit call button; nothing dials on its own.
                if ["US", "CA"].contains(model.household?.privateLocation?.countryCode?.uppercased() ?? "") {
                    PhoneRow(label: l("common.help.call911"), number: "911", systemImage: "phone.fill")
                        .listRowBackground(Theme.critical.opacity(0.08))
                } else {
                    Text(l("plan.help.localUnknown"))
                }
                if !model.capabilities.isOnline {
                    Label(l("common.offline"), systemImage: "wifi.slash").font(.footnote)
                }
                if model.household != nil {
                    Button { showCard = true } label: { Label(l("ui.card.open"), systemImage: "bolt.heart.fill") }
                        .foregroundStyle(Theme.critical)
                        .accessibilityIdentifier("help.outageCard")
                }
            }
            if model.content != nil {
                Section {
                    Button {
                        showMapPlanner = true
                    } label: {
                        Label("Plan with Apple Maps", systemImage: "map.fill")
                    }
                    .font(.headline)
                    .accessibilityIdentifier("help.openMap")
                } footer: {
                    Text("Browse verified directory places by county, search Apple Maps explicitly, and preview an ordinary trip. Location access is optional.")
                }
            }
            if let contacts = model.household?.contacts.filter({ $0.hasUsablePhone }), !contacts.isEmpty {
                Section(l("plan.section.contacts")) {
                    ForEach(contacts) { c in PhoneRow(label: "\(c.alias) · \(l("ui.contact.role.\(c.role.rawValue)"))", number: c.phone ?? "") }
                }
            }
            if PublicDataPolicy.isAllowedRegionID(regionID) {
                AlertsSection(regionID: regionID)
            } else {
                Section { Text(l("native.localHelp")) }
            }
            if let region {
                Section {
                    Text("\(region.name): \(coverageText(region.coverage))").font(.footnote)
                    if let note = region.coverageNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            ForEach(groups(resources), id: \.0) { type, items in
                Section(typeName(type)) {
                    ForEach(items) { ResourceRow(resource: $0) }
                }
            }
        }
        .navigationTitle(l("common.tab.help"))
        .sheet(isPresented: $showCard) { NavigationStack { OutageCardView() } }
        .sheet(isPresented: $showMapPlanner) {
            if let regionalResources = model.regionalResources {
                MapPlanningView(store: regionalResources)
            } else if let content = model.content {
                MapPlanningView(content: content, client: model.publicClient, regionID: regionID)
            } else {
                ProgressView("Loading map")
            }
        }
    }

    private func groups(_ resources: [PublicResource]) -> [(ResourceServiceType, [PublicResource])] {
        let order = ResourceServiceType.allCases
        return Dictionary(grouping: resources, by: \.serviceType)
            .sorted { (order.firstIndex(of: $0.key) ?? 0) < (order.firstIndex(of: $1.key) ?? 0) }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
    }

    private func coverageText(_ c: CoverageStatus) -> String {
        switch c {
        case .verifiedPartial: "some local resources verified"
        case .oemOnly: "emergency management office only"
        case .statewideOnly: "statewide resources only"
        case .notStarted: "local resources not yet verified; statewide resources shown"
        }
    }

    private func typeName(_ t: ResourceServiceType) -> String {
        switch t {
        case .emergencyManagement: "Emergency management"
        case .publicHealth: "Public health"
        case .waterProvider: "Water"
        case .electricUtility: "Electricity"
        case .transportation: "Transportation"
        case .assistanceLine: "Help lines"
        case .assistanceRegistry: "Assistance registry (opt-in)"
        case .disasterAssistance: "Disaster assistance"
        case .warmingCenter: "Warming sites"
        case .coolingCenter: "Cooling sites"
        case .shelter: "Shelters"
        case .alertEnrollment: "Alert sign-up"
        case .other: "Other"
        }
    }
}

struct ResourceRow: View {
    let resource: PublicResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resource.name).font(.body.weight(.semibold))
            Text(resource.summary).font(.callout)
            if let phone = resource.contact.phone {
                // Phone numbers are always shown as text so they remain useful offline and in print.
                HStack {
                    Text(phone).font(.callout.monospacedDigit()).textSelection(.enabled)
                    if let note = resource.contact.phoneNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let url = URL(string: "tel:\(phone.filter { $0.isNumber })") {
                        Link(destination: url) { Label("Call", systemImage: "phone") }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Opens the phone app. Dry Run never calls automatically.")
                    }
                }
            }
            if let site = resource.contact.url, let url = URL(string: site) {
                Link(destination: url) { Label("Official website", systemImage: "safari") }.font(.callout)
            }
            let display = PublicDataPolicy.activationDisplay(for: resource, now: Date())
            if display != .notApplicable {
                Text(activationText(display)).font(.caption.weight(.semibold))
            }
            HStack(spacing: 8) {
                Text("\(resource.publisher)")
                Text("Checked \(resource.checkedAt)")
                if resource.reviewState != .reviewed { Text("Needs review").foregroundStyle(Theme.caution) }
                if resource.classification == .demo || resource.classification == .fixture { Text("Demo data").foregroundStyle(Theme.critical) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Only unexpired source evidence can say a site is open; unknown is never shown as open or closed.
    private func activationText(_ d: PublicDataPolicy.ActivationDisplay) -> String {
        switch d {
        case .confirmedActive: "Activated (per official source)"
        case .confirmedInactive: "Not currently activated (per official source)"
        case .unconfirmed: "Activation not confirmed — check the official source before going"
        case .notApplicable: ""
        }
    }
}

struct DirectoryMapView: View {
    let resources: [PublicResource]
    var body: some View {
        Map {
            ForEach(resources) { r in
                if let latitude = r.latitude, let longitude = r.longitude,
                   let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude) {
                    Marker(r.name, systemImage: "building.2", coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .accessibilityLabel("Map of listed offices. The same places are listed above as text.")
    }
}

/// Official alerts. Current alerts are shown as current. Alerts still in effect but fetched a while ago (stale) are
/// shown with their dates, never dropped — an old tornado warning must not turn into "no alerts". Expired, cancelled,
/// and demo alerts are never shown as current. Offline shows the cached, dated envelope.
struct AlertsSection: View {
    @Environment(AppModel.self) private var model
    let regionID: String
    @State private var envelope: AlertsEnvelope?
    @State private var freshness: PublicAPIClient.Freshness?

    var body: some View {
        Section("Official alerts (National Weather Service)") {
            if let envelope, envelope.regionID == regionID {
                let now = Date()
                let current = PublicDataPolicy.currentOfficialAlerts(envelope.alerts, now: now)
                let stale = envelope.alerts.filter { PublicDataPolicy.freshness(of: $0, now: now) == .stale }
                if case .cached(let date) = freshness {
                    Label("Offline. Showing alerts saved \(date ?? envelope.fetchedAt).", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                }
                ForEach(current) { AlertRow(alert: $0, isStale: false) }
                ForEach(stale) { AlertRow(alert: $0, isStale: true) }
                if current.isEmpty && stale.isEmpty {
                    if freshness == .updated {
                        Text("No alerts in effect as of \(envelope.fetchedAt).").font(.callout)
                    } else {
                        Text("Current alert status is unknown. Check local media or weather.gov.").font(.callout)
                    }
                }
            } else {
                Text("Current conditions are unavailable right now. Rehearsals and your saved plan still work.").font(.callout)
            }
        }
        .task(id: regionID) {
            let (env, fresh) = await model.publicClient.refreshAlerts(regionID: regionID)
            // Never show data for a different county than the one requested.
            envelope = env?.regionID == regionID ? env : nil
            freshness = fresh
        }
    }
}

private struct AlertRow: View {
    let alert: PublicAlert
    let isStale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.event).font(.headline)
            if isStale {
                Text("May be out of date — last updated \(alert.fetchedAt). Check for newer information.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.caution)
            }
            if let headline = alert.headline { Text(headline).font(.callout) }
            Text("Issued \(alert.sent) · expires \(alert.expires ?? "unknown")").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
