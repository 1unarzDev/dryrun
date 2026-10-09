import Foundation

/// Builds a localized `PlanDocument` from immutable inputs. Pure and deterministic for a given `generatedAt`.
/// One essentials page plus one page per selected scenario (never six hazards squeezed onto one page).
public enum PlanBuilder {
    public struct Options: Sendable {
        public var includePrivateNotes: Bool
        public var maxPreparationsPerScenario: Int
        public var reviewedAt: Date?
        public init(includePrivateNotes: Bool = false, maxPreparationsPerScenario: Int = 3, reviewedAt: Date? = nil) {
            self.includePrivateNotes = includePrivateNotes
            self.maxPreparationsPerScenario = maxPreparationsPerScenario
            self.reviewedAt = reviewedAt
        }
    }

    public static func build(
        household: HouseholdProfile,
        home: HomeModel,
        results: [RehearsalResult],
        localizer l: Localizer,
        resources: [PublicResource],
        contentVersion: String,
        generatedAt: Date,
        options: Options = Options()
    ) -> PlanDocument {
        let b = Builder(l: l)
        var pages: [PlanPage] = [essentialsPage(b, household, home, resources, contentVersion, generatedAt, options)]
        for result in results.sorted(by: { order($0.input.scenarioID) < order($1.input.scenarioID) }) {
            pages.append(scenarioPage(b, result, household, home, resources, options))
        }
        let anyDraft = b.usedDraft
        let anyFallback = b.usedFallback
        return PlanDocument(
            schemaVersion: PlanDocument.schemaVersion, locale: l.locale, householdID: household.id,
            householdRevision: household.revision, homeID: home.id, homeRevision: home.revision,
            contentVersion: contentVersion, generatedAt: generatedAt, reviewedAt: options.reviewedAt,
            scenarioIDs: results.map(\.input.scenarioID), includesPrivateNotes: options.includePrivateNotes,
            pages: pages,
            draftTranslationBanner: anyDraft ? l.text("plan.draftBanner").text : nil,
            fallbackNote: anyFallback ? l.text("plan.fallbackNote").text : nil,
            contentReviewBanner: l.text("plan.contentDraftBanner").text,
            footer: l.text("plan.footer.practice").text,
            sourceIDs: Array(Set(b.sourceIDs)).sorted()
        )
    }

    static let scenarioOrder = ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"]
    static func order(_ id: String) -> Int { scenarioOrder.firstIndex(of: id) ?? 99 }

    // MARK: - Pages

    private static func essentialsPage(_ b: Builder, _ h: HouseholdProfile, _ home: HomeModel, _ resources: [PublicResource],
                                       _ contentVersion: String, _ generatedAt: Date, _ options: Options) -> PlanPage {
        var sections: [PlanSection] = []

        // People and assistance (needs as plain labels, no diagnosis).
        var people: [PlanLine] = h.people.map { p in
            let needs = p.needs.isEmpty ? b.l("plan.person.noNeeds") : p.needs.map { b.l("common.need.\($0.rawValue)") }.joined(separator: ", ")
            return b.line("plan.person.line", ["alias": p.alias, "needs": needs])
        }
        for p in h.people {
            if let helperID = p.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }) {
                people.append(b.line("plan.person.helper", ["helper": helper.alias, "alias": p.alias]))
            }
        }
        sections.append(b.section("people", "plan.section.people", people, critical: false))

        sections.append(b.section("meeting", "plan.section.meeting", [meetingLine(b, home)], critical: true))

        let contacts: [PlanLine] = h.contacts.isEmpty ? [b.line("plan.contact.none")] : h.contacts.map { c in
            c.phone.map { b.line("plan.contact.line", ["alias": c.alias, "phone": $0], style: .contact) }
                ?? b.line("plan.contact.noPhone", ["alias": c.alias])
        }
        sections.append(b.section("contacts", "plan.section.contacts", contacts, critical: true))
        sections.append(b.section("help", "plan.section.help", helpLines(b, resources), critical: true))

        if !h.equipment.isEmpty {
            sections.append(b.section("equipment", "plan.section.equipment", equipmentLines(b, h, options), critical: true))
        }
        sections.append(b.section("transport", "plan.section.transport", transportLines(b, h), critical: false))
        sections.append(b.section("water", "plan.section.water", waterLines(b, h), critical: false))

        var dates = [b.line("plan.dates.line", [
            "generated": isoDay(generatedAt), "householdRevision": "\(h.revision)",
            "homeRevision": "\(home.revision)", "contentVersion": contentVersion,
        ])]
        dates.append(options.reviewedAt.map { b.line("plan.dates.reviewed", ["reviewed": isoDay($0)]) } ?? b.line("plan.dates.notReviewed"))
        sections.append(b.section("dates", "plan.section.dates", dates, critical: false))

        return PlanPage(id: "essentials", kind: .essentials, title: b.l("plan.title.essentials"), sections: sections)
    }

    private static func scenarioPage(_ b: Builder, _ r: RehearsalResult, _ h: HouseholdProfile, _ home: HomeModel,
                                     _ resources: [PublicResource], _ options: Options) -> PlanPage {
        let id = r.input.scenarioID
        let sources = b.l("plan.scenario.\(id).sources").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var sections: [PlanSection] = []

        var immediate: [PlanLine] = []
        var i = 1
        while b.localizer.has("plan.scenario.\(id).immediate.\(i)", in: "en") {
            let key = "plan.scenario.\(id).immediate.\(i)"
            // Classify from the source-language text so a prohibition keeps its emphasis in every locale.
            let source = b.localizer.with(locale: b.localizer.sourceLocale).text(key).text.lowercased()
            let style: PlanLineStyle = (source.contains("never") || source.contains("do not") || source.contains("don't")) ? .prohibition : .normal
            immediate.append(b.line(key, style: style, sources: sources))
            i += 1
        }
        sections.append(b.section("immediate", "plan.section.immediate", immediate, critical: true))

        if id == "home-fire" || id == "tornado" || id == "flash-flood" {
            var homePlan: [PlanLine] = []
            if id == "tornado" {
                if h.housing.homeType == .manufacturedHome {
                    homePlan.append(b.line("plan.shelter.manufactured", style: .prohibition, sources: ["S22"]))
                } else if let shelter = home.annotations.first(where: { $0.kind == .tornadoShelterCandidate }) {
                    let label = shelter.spaceID.flatMap { home.space($0)?.label } ?? shelter.label
                    homePlan.append(b.line("plan.shelter.line", ["label": label], sources: ["S22"]))
                    homePlan.append(b.line("plan.shelter.notCertified", style: .caveat))
                } else {
                    homePlan.append(b.line("plan.shelter.missing"))
                }
                sections.append(b.section("shelter", "plan.section.shelter", homePlan, critical: true))
            } else if id == "home-fire" {
                homePlan.append(contentsOf: routeLines(b, r.routes, home, h))
                homePlan.append(meetingLine(b, home))
                homePlan.append(b.line("plan.route.caveat", style: .caveat))
                sections.append(b.section("homeplan", "plan.section.homeplan", homePlan, critical: true))
            } else {
                sections.append(b.section("transport", "plan.section.transport", transportLines(b, h), critical: true))
            }
        } else {
            sections.append(b.section("transport", "plan.section.transport", transportLines(b, h), critical: false))
        }

        let assists = h.people.compactMap { p -> PlanLine? in
            guard let helperID = p.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }) else { return nil }
            return b.line("plan.person.helper", ["helper": helper.alias, "alias": p.alias])
        }
        if !assists.isEmpty { sections.append(b.section("assistance", "plan.section.assistance", assists, critical: true)) }

        if !h.equipment.isEmpty && ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood"].contains(id) {
            sections.append(b.section("equipment", "plan.section.equipment", equipmentLines(b, h, options), critical: true))
        }
        if id == "water-outage" || id == "freeze-power-loss" {
            sections.append(b.section("water", "plan.section.water", waterLines(b, h), critical: false))
        }

        let preps = r.recommendations.prefix(options.maxPreparationsPerScenario).map { rec in
            b.line(rec.titleKey, rec.templateValues, sources: rec.sourceIDs)
        }
        if !preps.isEmpty { sections.append(b.section("preparations", "plan.section.preparations", Array(preps), critical: false)) }

        sections.append(b.section("help", "plan.section.help", helpLines(b, resources), critical: true))

        let title = b.l("plan.title.scenario", ["scenario": b.l("common.scenario.\(id)")])
        return PlanPage(id: "scenario-\(id)", kind: .scenario(id), title: title, sections: sections)
    }

    // MARK: - Shared sections

    private static func meetingLine(_ b: Builder, _ home: HomeModel) -> PlanLine {
        if let m = home.meetingPoint, m.verification == .verified {
            return b.line("plan.meeting.line", ["label": m.label], sources: ["S19"])
        }
        return b.line("plan.meeting.missing", sources: ["S19"])
    }

    private static func helpLines(_ b: Builder, _ resources: [PublicResource]) -> [PlanLine] {
        var lines = [b.line("plan.help.911", style: .contact)]
        let phoneTypes: Set<ResourceServiceType> = [.assistanceLine, .emergencyManagement, .electricUtility, .waterProvider, .assistanceRegistry]
        for r in resources where phoneTypes.contains(r.serviceType) {
            guard let phone = r.contact.phone else { continue }
            var line = r.contact.phoneNote.map {
                b.line("plan.help.lineNote", ["name": r.name, "phone": phone, "note": $0], style: .contact, sources: r.sourceIDs)
            } ?? b.line("plan.help.line", ["name": r.name, "phone": phone], style: .contact, sources: r.sourceIDs)
            // Public pack names/notes are English source data; label them as English in other locales.
            if b.localizer.locale != "en" {
                line.isFallback = true
                b.usedFallback = true
            }
            lines.append(line)
        }
        return lines
    }

    private static func equipmentLines(_ b: Builder, _ h: HouseholdProfile, _ options: Options) -> [PlanLine] {
        var lines: [PlanLine] = []
        for eq in h.equipment where eq.isEssential {
            let confirmedBackups = eq.compatibleBackupIDs.filter { id in
                h.backupPower.first(where: { $0.id == id })?.setupConfirmed.confirmedValue == true
            }
            let state: String
            if !confirmedBackups.isEmpty { state = b.l("plan.equipment.backup.confirmed") }
            else if eq.compatibleBackupIDs.isEmpty && h.backupPower.isEmpty { state = b.l("plan.equipment.backup.none") }
            else { state = b.l("plan.equipment.backup.unconfirmed") }
            let runtime = eq.documentedBackupRuntimeHours.confirmedValue.map {
                b.l("plan.equipment.runtimeKnown", ["hours": formatNumber($0)])
            } ?? b.l("plan.equipment.runtimeUnknown")
            lines.append(b.line("plan.equipment.line", ["label": eq.label, "backupState": state, "runtime": runtime], sources: ["S25"]))
            if let notes = eq.carePlanNotes, !notes.isEmpty, options.includePrivateNotes {
                lines.append(PlanLine(text: notes, style: .normal, key: "private.carePlanNotes", resolvedLocale: b.localizer.locale,
                                      isFallback: false, isDraftTranslation: false, sourceIDs: []))
            }
        }
        if !options.includePrivateNotes && h.equipment.contains(where: { !($0.carePlanNotes ?? "").isEmpty }) {
            lines.append(b.line("plan.equipment.carePlanPrivate", style: .caveat))
        }
        return lines
    }

    private static func transportLines(_ b: Builder, _ h: HouseholdProfile) -> [PlanLine] {
        var lines: [PlanLine] = h.transport.vehicles.map { b.line("plan.transport.vehicle", ["seats": "\($0.seats)"]) }
        if !h.transport.hasVehicle { lines.append(b.line("plan.transport.noVehicle")) }
        for alt in h.transport.alternatives {
            let agreed = alt.agreed.confirmedValue == true ? b.l("plan.transport.agreed") : b.l("plan.transport.notAgreed")
            lines.append(b.line("plan.transport.alternative", ["kind": b.l("common.transport.\(alt.kind.rawValue)"), "agreed": agreed]))
        }
        if h.transport.alternatives.isEmpty && !h.transport.hasVehicle { lines.append(b.line("plan.transport.none")) }
        return lines
    }

    private static func waterLines(_ b: Builder, _ h: HouseholdProfile) -> [PlanLine] {
        let target = WaterTarget.storageTargetGallons(people: h.people.count, days: 3)
        let stored = h.supplies.storedWaterGallons.value.map { b.l("plan.water.storedGallons", ["gallons": formatNumber($0)]) }
            ?? b.l("plan.water.storedUnknown")
        var lines = [b.line("plan.water.target", ["people": "\(h.people.count)", "targetGallons": formatNumber(target), "storedGallons": stored], sources: ["S26"])]
        if !h.pets.isEmpty { lines.append(b.line("plan.water.pets", sources: ["S26"])) }
        return lines
    }

    private static func routeLines(_ b: Builder, _ routes: [RouteResult], _ home: HomeModel, _ h: HouseholdProfile) -> [PlanLine] {
        var lines: [PlanLine] = []
        var seenStarts = Set<String>()
        for route in routes where seenStarts.insert(route.request.startSpaceID).inserted {
            let start = home.space(route.request.startSpaceID)?.label ?? route.request.startSpaceID
            if let primary = route.primary {
                lines.append(b.line("plan.route.from", ["start": start, "steps": steps(primary, home)], sources: ["S19"]))
                switch route.alternativeStatus {
                case .independent:
                    if let alt = route.alternative {
                        lines.append(b.line("plan.route.alt", ["start": start, "steps": steps(alt, home)], sources: ["S19"]))
                    }
                case .sharesChokepoint:
                    let choke = route.sharedChokepoints.compactMap { home.space($0)?.label }.first ?? route.sharedChokepoints.first ?? "?"
                    lines.append(b.line("plan.route.altShared", ["start": start, "chokepoint": choke], style: .caveat))
                case .none:
                    lines.append(b.line("plan.route.altNone", ["start": start], style: .caveat))
                }
            } else {
                let reason = b.l("plan.route.reason.\((route.noRouteReason ?? .incompleteConnectivity).rawValue)")
                lines.append(b.line("plan.route.none", ["start": start, "reason": reason], style: .caveat))
            }
        }
        return lines
    }

    private static func steps(_ path: RoutePath, _ home: HomeModel) -> String {
        (path.spaceSequence.map { home.space($0)?.label ?? $0 } + ["⟶ outside"]).joined(separator: " → ")
            .replacingOccurrences(of: "→ ⟶", with: "→")
    }

    static func formatNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func isoDay(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: d)
    }

    // MARK: - Line builder tracking fallback/draft state

    /// Records draft/fallback state for EVERY resolved string (titles and headings too, not only lines).
    final class Builder {
        let localizer: Localizer
        var sourceIDs: [String] = []
        var usedDraft = false
        var usedFallback = false
        init(l: Localizer) { localizer = l }

        func l(_ key: String, _ values: [String: String] = [:]) -> String { track(localizer.text(key, values)).text }

        @discardableResult
        func track(_ t: LocalizedText) -> LocalizedText {
            if t.needsDraftLabel { usedDraft = true }
            if t.isFallback { usedFallback = true }
            return t
        }

        func line(_ key: String, _ values: [String: String] = [:], style: PlanLineStyle = .normal, sources: [String] = []) -> PlanLine {
            let t = track(localizer.text(key, values))
            sourceIDs.append(contentsOf: sources)
            return PlanLine(text: t.text, style: style, key: key, resolvedLocale: t.resolvedLocale,
                            isFallback: t.isFallback, isDraftTranslation: t.needsDraftLabel, sourceIDs: sources)
        }

        func section(_ id: String, _ headingKey: String, _ lines: [PlanLine], critical: Bool) -> PlanSection {
            PlanSection(id: id, heading: l(headingKey), lines: lines, isSafetyCritical: critical)
        }
    }
}

/// CDC emergency STORAGE target: 1 gallon per person per day [S26]. Not a prescribed drinking volume.
public enum WaterTarget {
    public static let gallonsPerPersonPerDay = 1.0
    public static func storageTargetGallons(people: Int, days: Int) -> Double {
        Double(people) * Double(days) * gallonsPerPersonPerDay
    }
}
