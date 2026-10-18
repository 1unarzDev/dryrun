import Foundation

/// Builds a localized `PlanDocument` from immutable inputs. Pure and deterministic for a given `generatedAt`.
/// One essentials page plus one page per selected scenario (never six hazards squeezed onto one page).
public enum PlanBuilder {
    public struct Options: Sendable {
        public var familyCardSelection: FamilyCardSelection
        public var includePrivateNotes: Bool
        public var maxPreparationsPerScenario: Int
        public var reviewedAt: Date?
        /// Calendar days in the plan ("generated", "reviewed") are the household's local days. Defaults to UTC so a
        /// build stays deterministic; the app passes the device's time zone.
        public var timeZone: TimeZone
        public init(includePrivateNotes: Bool = false, familyCardSelection: FamilyCardSelection = FamilyCardSelection(), maxPreparationsPerScenario: Int = 3, reviewedAt: Date? = nil,
                    timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
            self.familyCardSelection = familyCardSelection
            self.includePrivateNotes = includePrivateNotes
            self.maxPreparationsPerScenario = maxPreparationsPerScenario
            self.reviewedAt = reviewedAt
            self.timeZone = timeZone
        }
    }

    public static func build(
        household: HouseholdProfile,
        home: HomeModel?,
        savedPlaces: [SavedPlace] = [],
        results: [RehearsalResult],
        localizer l: Localizer,
        resources: [PublicResource],
        contentVersion: String,
        generatedAt: Date,
        options: Options = Options()
    ) -> PlanDocument {
        let b = Builder(l: l)
        let matchingPlaces = HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: savedPlaces, recordedAt: household.updatedAt).filter { $0.homeID == (home?.id ?? household.stableHomeID) }
        var pages: [PlanPage] = [FamilyEmergencyCardBuilder.page(household: household, savedPlaces: matchingPlaces, builder: b, selection: options.familyCardSelection, timeZone: options.timeZone), essentialsPage(b, household, home, matchingPlaces, resources, contentVersion, generatedAt, options)]
        for result in results.sorted(by: { order($0.input.scenarioID) < order($1.input.scenarioID) }) {
            pages.append(scenarioPage(b, result, household, home, resources, options))
        }
        b.sourceIDs.append(contentsOf: pages.flatMap(\.sections).flatMap(\.lines).flatMap(\.sourceIDs))
        var visualSnapshot = PlanVisualSnapshot(home: exportHome(home, options: options, localizer: l), routes: results.flatMap { currentRoutes($0) }, savedPlaces: matchingPlaces.sorted { $0.id < $1.id }, homeCoordinate: household.privateLocation.flatMap { location in
                guard let lat = location.latitude, let lon = location.longitude else { return nil }; return GeographicCoordinate(latitude: lat, longitude: lon)
            }, fictional: household.isFictional || home?.source == .sample || home?.isFictional == true, routeScenarioIDs: results.flatMap { result in currentRoutes(result).map { _ in result.input.scenarioID } }, personLabels: Dictionary(uniqueKeysWithValues: household.people.map { ($0.id, $0.localizedLabel(l)) }), scenarioLabels: scenarioLabels(results, localizer: l), exerciseStates: results.compactMap { result in
                guard let state = result.snapshots.last(where: { $0.spatialState != nil })?.spatialState else { return nil }
                return PlanExerciseSnapshot(scenarioID: result.input.scenarioID, state: state)
            })
        visualSnapshot.panelDetails = Dictionary(uniqueKeysWithValues: visualSnapshot.homePanels.map { ($0.id, $0.details(in: visualSnapshot, localizer: l)) })
        let anyDraft = b.usedDraft
        let anyFallback = b.usedFallback
        return PlanDocument(
            schemaVersion: PlanDocument.schemaVersion, locale: l.locale, householdID: household.id,
            householdRevision: household.revision, homeID: home?.id ?? household.stableHomeID, homeRevision: home?.revision ?? 0,
            contentVersion: contentVersion, generatedAt: generatedAt, reviewedAt: options.reviewedAt,
            scenarioIDs: results.map(\.input.scenarioID), includesPrivateNotes: options.includePrivateNotes,
            pages: pages,
            draftTranslationBanner: anyDraft ? draftBanner(l) : nil,
            fallbackNote: anyFallback ? l.text("plan.fallbackNote").text : nil,
            contentReviewBanner: l.text("plan.contentDraftBanner").text,
            footer: l.text("plan.footer.practice").text,
            sourceIDs: Array(Set(b.sourceIDs)).sorted(),
            visualSnapshot: visualSnapshot
        )
    }

    /// Localized banner plus the exact English wording, so any reader (and reviewers) can see the draft state.
    static func draftBanner(_ l: Localizer) -> String {
        let english = l.with(locale: l.sourceLocale).text("plan.draftBanner").text
        let local = l.text("plan.draftBanner").text
        return local == english ? english : "\(local) / \(english)"
    }

    static let scenarioOrder = ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"]
    static func order(_ id: String) -> Int { scenarioOrder.firstIndex(of: id) ?? 99 }

    static func scenarioLabelKey(_ result: RehearsalResult) -> String {
        isHouseholdLeak(result) ? "scenario.household-leak.title" : "common.scenario.\(result.input.scenarioID)"
    }

    private static func isHouseholdLeak(_ result: RehearsalResult) -> Bool {
        result.input.scenarioID == "flash-flood" && result.input.effectiveSpatialOptions.floodIsHouseholdLeak
    }

    private static func scenarioLabels(_ results: [RehearsalResult], localizer: Localizer) -> [String: String] {
        Dictionary(grouping: results, by: { $0.input.scenarioID }).mapValues { matching in
            Set(matching.map { localizer(scenarioLabelKey($0)) }).sorted().joined(separator: " / ")
        }
    }

    // MARK: - Pages

    private static func essentialsPage(_ b: Builder, _ h: HouseholdProfile, _ home: HomeModel?, _ places: [SavedPlace], _ resources: [PublicResource],
                                       _ contentVersion: String, _ generatedAt: Date, _ options: Options) -> PlanPage {
        var sections: [PlanSection] = []

        // People and assistance (needs as plain labels, no diagnosis).
        var people: [PlanLine] = h.people.map { p in
            let needs = (!options.familyCardSelection.includeCriticalInformation || p.needs.isEmpty) ? b.l("family.notProvidedSelected") : p.needs.map { b.l("common.need.\($0.rawValue)") }.joined(separator: ", ")
            return b.line("plan.person.line", ["alias": p.localizedLabel(b.localizer), "needs": needs])
        }
        for p in h.people where options.familyCardSelection.includeCriticalInformation {
            if let helperID = p.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }) {
                people.append(b.line("plan.person.helper", ["helper": helper.localizedLabel(b.localizer), "alias": p.localizedLabel(b.localizer)]))
            }
        }
        sections.append(b.section("people", "plan.section.people", people, critical: false))

        sections.append(b.section("meeting", "plan.section.meeting", meetingLines(b, home, places), critical: true))
        if !places.isEmpty {
            let lines = places.sorted { $0.id < $1.id }.enumerated().flatMap { index, place in
                PlanPlacePresentation.lines(for: place, number: index + 1, localizer: b.localizer)
            }
            b.usedFallback = b.usedFallback || lines.contains(where: \.isFallback)
            b.usedDraft = b.usedDraft || lines.contains(where: \.isDraftTranslation)
            sections.append(b.section("neighborhood", "map.neighborhood", lines, critical: false))
        }

        let contacts: [PlanLine] = h.contacts.isEmpty ? [b.line("plan.contact.none")] : h.contacts.map { c in
            c.phone.map { b.line("plan.contact.line", ["alias": c.alias, "phone": $0], style: .contact) }
                ?? b.line("plan.contact.noPhone", ["alias": c.alias])
        }
        if options.familyCardSelection.includeContacts { sections.append(b.section("contacts", "plan.section.contacts", contacts, critical: true)) }
        sections.append(b.section("help", "plan.section.help", helpLines(b, resources, countryCode: h.privateLocation?.countryCode), critical: true))

        if !h.equipment.isEmpty && (options.familyCardSelection.includeCriticalInformation || options.familyCardSelection.includeMedication || options.includePrivateNotes), !equipmentLines(b, h, options).isEmpty {
            sections.append(b.section("equipment", "plan.section.equipment", equipmentLines(b, h, options), critical: true))
        }
        sections.append(b.section("transport", "plan.section.transport", transportLines(b, h), critical: false))
        sections.append(b.section("water", "plan.section.water", waterLines(b, h), critical: false))

        var dates = [b.line("plan.dates.line", [
            "generated": isoDay(generatedAt, options.timeZone), "householdRevision": "\(h.revision)",
            "homeRevision": "\(home?.revision ?? 0)", "contentVersion": contentVersion,
        ])]
        dates.append(options.reviewedAt.map { b.line("plan.dates.reviewed", ["reviewed": isoDay($0, options.timeZone)]) } ?? b.line("plan.dates.notReviewed"))
        sections.append(b.section("dates", "plan.section.dates", dates, critical: false))

        return PlanPage(id: "essentials", kind: .essentials, title: b.l("plan.title.essentials"), sections: sections)
    }

    private static func scenarioPage(_ b: Builder, _ r: RehearsalResult, _ h: HouseholdProfile, _ home: HomeModel?,
                                     _ resources: [PublicResource], _ options: Options) -> PlanPage {
        let id = r.input.scenarioID
        let leak = isHouseholdLeak(r)
        let contentID = leak ? "household-leak" : id
        let sources = b.l("plan.scenario.\(contentID).sources").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var sections: [PlanSection] = []

        var immediate: [PlanLine] = []
        var i = 1
        while b.localizer.has("plan.scenario.\(contentID).immediate.\(i)", in: "en") {
            let key = "plan.scenario.\(contentID).immediate.\(i)"
            // Classify from the source-language text so a prohibition keeps its emphasis in every locale.
            let source = b.localizer.with(locale: b.localizer.sourceLocale).text(key).text.lowercased()
            let style: PlanLineStyle = (source.contains("never") || source.contains("do not") || source.contains("don't")) ? .prohibition : .normal
            let emergencyNumber = ["US", "CA"].contains(h.privateLocation?.countryCode?.uppercased() ?? "")
                ? "911" : b.l("plan.help.emergencyNumber.local")
            let numberSources = source.contains("{emergencynumber}") && h.privateLocation?.countryCode?.uppercased() == "CA" ? ["S56"] : []
            immediate.append(b.line(key, ["emergencyNumber": emergencyNumber], style: style, sources: sources + numberSources))
            i += 1
        }
        if leak { immediate.append(b.line("plan.scenario.household-leak.sourceScope", style: .caveat, sources: sources)) }
        sections.append(b.section("immediate", "plan.section.immediate", immediate, critical: true))

        if id == "home-fire" || id == "tornado" || id == "flash-flood" {
            var homePlan: [PlanLine] = []
            if home == nil {
                homePlan.append(b.line("map.layoutMissing", style: .caveat))
                sections.append(b.section("homeplan", "plan.section.homeplan", homePlan, critical: true))
            } else if let home, leak {
                let affectedIDs = r.snapshots.last(where: { $0.spatialState != nil })?.spatialState?.affectedSpaceIDs
                    ?? r.input.effectiveSpatialOptions.floodAffectedSpaceIDs
                let rooms = Array(Set(affectedIDs)).sorted().compactMap { home.space($0)?.label }
                homePlan.append(rooms.isEmpty ? b.line("plan.scenario.household-leak.areaUnknown")
                    : b.line("plan.scenario.household-leak.affected", ["rooms": rooms.joined(separator: ", ")]))
                homePlan.append(b.line("plan.scenario.household-leak.noRoute", style: .caveat, sources: sources))
                sections.append(b.section("homeplan", "plan.section.homeplan", homePlan, critical: true))
            } else if let home, id == "tornado" {
                if h.housing.homeType == .manufacturedHome {
                    homePlan.append(b.line("plan.shelter.manufactured", style: .prohibition, sources: ["S22"]))
                } else if let shelter = currentShelter(r, home: home) {
                    homePlan.append(b.line("plan.shelter.line", ["label": shelter.label], sources: ["S22"]))
                    homePlan.append(b.line("plan.shelter.notCertified", style: .caveat))
                } else {
                    homePlan.append(b.line("plan.shelter.missing"))
                }
                homePlan.append(contentsOf: routeLines(b, currentRoutes(r), home, h))
                sections.append(b.section("shelter", "plan.section.shelter", homePlan, critical: true))
            } else if let home, id == "home-fire" {
                homePlan.append(contentsOf: routeLines(b, currentRoutes(r), home, h))
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
            guard options.familyCardSelection.includeCriticalInformation else { return nil }
            guard let helperID = p.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }) else { return nil }
            return b.line("plan.person.helper", ["helper": helper.localizedLabel(b.localizer), "alias": p.localizedLabel(b.localizer)])
        }
        if !assists.isEmpty { sections.append(b.section("assistance", "plan.section.assistance", assists, critical: true)) }

        if (options.familyCardSelection.includeCriticalInformation || options.familyCardSelection.includeMedication || options.includePrivateNotes) && !h.equipment.isEmpty && ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood"].contains(id), !equipmentLines(b, h, options).isEmpty {
            sections.append(b.section("equipment", "plan.section.equipment", equipmentLines(b, h, options), critical: true))
        }
        if id == "water-outage" || id == "freeze-power-loss" {
            sections.append(b.section("water", "plan.section.water", waterLines(b, h), critical: false))
        }

        let selectedRecommendations = r.recommendations.filter { rec in
            guard !options.familyCardSelection.includeCriticalInformation else { return true }
            let subject = rec.subjectID ?? ""
            let sensitiveSubject = ["person.", "equipment.", "backup."].contains { subject.hasPrefix($0) }
            let sensitiveValues = !Set(rec.templateValues.keys).isDisjoint(with: ["person", "device", "helper", "backup"])
            return !sensitiveSubject && !sensitiveValues && !rec.actionID.contains("medical") && !rec.actionID.contains("assist") && !rec.actionID.contains("backup")
        }
        let preps = selectedRecommendations.prefix(options.maxPreparationsPerScenario).map { rec in
            b.line(rec.titleKey, rec.localizedTemplateValues(household: h, localizer: b.localizer), sources: rec.sourceIDs)
        }
        if !preps.isEmpty { sections.append(b.section("preparations", "plan.section.preparations", Array(preps), critical: false)) }

        sections.append(b.section("help", "plan.section.help", helpLines(b, resources, countryCode: h.privateLocation?.countryCode), critical: true))

        let title = b.l("plan.title.scenario", ["scenario": b.l(scenarioLabelKey(r))])
        return PlanPage(id: "scenario-\(id)", kind: .scenario(id), title: title, sections: sections)
    }

    // MARK: - Shared sections

    /// Export the exercise's actual supported destination, never independently select a shelter from annotations.
    /// Old results without a canonical scene cannot establish which candidate the exercise accepted.
    static func currentShelter(_ result: RehearsalResult, home: HomeModel) -> Space? {
        guard let state = result.snapshots.last(where: { $0.spatialState != nil })?.spatialState,
              state.hazard == .tornado, let id = state.destinationSpaceID,
              let destination = home.space(id),
              state.routes.contains(where: {
                  $0.homeID == home.id && $0.homeRevision == home.revision &&
                  $0.request.purpose == .interiorShelter && $0.request.destinationSpaceID == id && $0.primary != nil
              }),
              EgressPlanner().plan(RouteRequest(startSpaceID: id, purpose: .interiorShelter, destinationSpaceID: id), in: home).primary != nil
        else { return nil }
        return destination
    }

    /// Legacy results could retain route history. Prefer the final canonical stage, including an empty/no-route stage.
    static func currentRoutes(_ result: RehearsalResult) -> [RouteResult] {
        if let state = result.snapshots.last(where: { $0.spatialState != nil })?.spatialState { return state.routes }
        var seen = Set<String>()
        return result.routes.reversed().filter { route in
            seen.insert("\(route.request.personID ?? "")|\(route.request.startSpaceID)|\(route.request.mobility.requiresStepFree)|\(route.request.purpose?.rawValue ?? "outdoorEgress")").inserted
        }.reversed()
    }

    /// User-authored room names remain part of the selected home diagram. Annotation free text is omitted
    /// unless its corresponding critical-information control is selected; private-notes consent is independent.
    private static func exportHome(_ home: HomeModel?, options: Options, localizer: Localizer) -> HomeModel? {
        guard var home else { return nil }
        if !options.familyCardSelection.includeCriticalInformation {
            home.annotations.removeAll { $0.kind == .medicalEquipment || $0.kind == .supplies }
        }
        // Notes are not drawn but are also removed from the shared render snapshot.
        for i in home.annotations.indices {
            home.annotations[i].note = nil
            if options.familyCardSelection.includeCriticalInformation {
                home.annotations[i].label = home.annotations[i].localizedLabel(localizer)
            } else { home.annotations[i].label = "" }
        }
        for i in home.portals.indices { home.portals[i].note = nil }
        return home
    }

    private static func meetingLines(_ b: Builder, _ home: HomeModel?, _ places: [SavedPlace]) -> [PlanLine] {
        let selected = places.filter { $0.homeID == (home?.id ?? "") || home == nil }
            .filter { $0.purpose == .outsideMeetingPoint || $0.purpose == .backupMeetingPlace }
            .sorted { ($0.purpose == .outsideMeetingPoint ? 0 : 1, $0.id) < ($1.purpose == .outsideMeetingPoint ? 0 : 1, $1.id) }
        if !selected.isEmpty { return selected.map { place in
            let purpose = b.l(place.purpose == .outsideMeetingPoint ? "plan.meeting.near" : "plan.meeting.backup")
            let detail = [place.label, place.addressText, place.findingInstructions].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            return PlanLine(text: "\(purpose): \(detail)", style: .normal, key: "private.meeting", resolvedLocale: b.localizer.locale, isFallback: false, isDraftTranslation: false, sourceIDs: ["S19"])
        } }
        return [home.map { meetingLine(b, $0) } ?? b.line("plan.meeting.missing", sources: ["S19"])]
    }

    private static func meetingLine(_ b: Builder, _ home: HomeModel) -> PlanLine {
        if let m = home.meetingPoint, m.verification == .verified {
            return b.line("plan.meeting.line", ["label": m.localizedLabel(b.localizer)], sources: ["S19"])
        }
        return b.line("plan.meeting.missing", sources: ["S19"])
    }

    static func helpLines(_ b: Builder, _ resources: [PublicResource], countryCode: String? = nil) -> [PlanLine] {
        // US/Canada 911 only with explicit country metadata; unknown countries need a local number recorded.
        let country = countryCode?.uppercased() ?? ""
        let sources = country == "CA" ? ["S56"] : (country == "US" ? ["S19"] : [])
        var lines = [b.line(["US", "CA"].contains(country) ? "plan.help.911" : "plan.help.localUnknown", style: .contact, sources: sources)]
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
            let includeDevice = eq.purpose == .refrigeratedMedication ? options.familyCardSelection.includeMedication : options.familyCardSelection.includeCriticalInformation
            guard includeDevice else {
                if options.includePrivateNotes, let note = eq.carePlanNotes, !note.isEmpty {
                    lines.append(PlanLine(text: note, style: .normal, key: "private.carePlanNotes", resolvedLocale: b.localizer.locale, isFallback: false, isDraftTranslation: false, sourceIDs: []))
                }
                continue
            }
            if eq.requiresColdStorage {
                let storage = eq.storageInstructions?.isEmpty == false ? eq.storageInstructions! : b.l("family.providerPrompt")
                lines.append(PlanLine(text: eq.localizedLabel(b.localizer) + ": " + storage, style: .normal, key: "private.storageInstructions", resolvedLocale: b.localizer.locale, isFallback: false, isDraftTranslation: false, sourceIDs: ["S54"]))
            }
            if eq.requiresElectricalPower {
                let assignment = MedicalBackupReadiness.assignment(for: eq, in: h)
                let state: String
                if assignment?.state == .operational { state = b.l("plan.equipment.backup.confirmed") }
                else if eq.compatibleBackupIDs.isEmpty && h.backupPower.isEmpty { state = b.l("plan.equipment.backup.none") }
                else { state = b.l("plan.equipment.backup.unconfirmed") }
                let runtime = eq.documentedBackupRuntimeHours.confirmedValue.map {
                    b.l("plan.equipment.runtimeKnown", ["hours": formatNumber($0, locale: b.localizer.locale)])
                } ?? b.l("plan.equipment.runtimeUnknown")
                lines.append(b.line("plan.equipment.line", ["label": eq.localizedLabel(b.localizer), "backupState": state, "runtime": runtime], sources: ["S25"]))
                if let assignment, assignment.state != .operational {
                    lines.append(b.line("card.backup.prerequisites", ["reason": b.l("reason.\(assignment.reason)")], style: .caveat, sources: ["S25"]))
                }
            }
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

    /// The family card and full plan retain the same explicitly recorded continuity destinations.
    /// A household confirmation cannot establish activation of a public shelter or cooling/warming site.
    static func continuityDestinationLines(_ b: Builder, _ h: HouseholdProfile) -> [PlanLine] {
        let destinations = h.transport.destinations.filter {
            $0.conditionsConfirmed.confirmedValue == true && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if destinations.isEmpty {
            return h.transport.destinations.isEmpty ? [] : [b.line("card.goTo.none", style: .caveat, sources: ["S52"])]
        }
        return destinations.map { destination in
            let publicSite = destination.kind == .publicShelter || destination.kind == .publicWarmingOrCoolingSite
            return b.line(publicSite ? "plan.transport.destination.public" : "plan.transport.destination.recorded",
                          ["place": destination.label], sources: ["S52"])
        }
    }

    private static func transportLines(_ b: Builder, _ h: HouseholdProfile) -> [PlanLine] {
        var lines: [PlanLine] = h.transport.vehicles.map { b.line("plan.transport.vehicle", ["seats": "\($0.seats)"]) }
        if !h.transport.hasVehicle { lines.append(b.line("plan.transport.noVehicle")) }
        for alt in h.transport.alternatives {
            let agreed = alt.agreed.confirmedValue == true ? b.l("plan.transport.agreed") : b.l("plan.transport.notAgreed")
            lines.append(b.line("plan.transport.alternative", ["kind": b.l("common.transport.\(alt.kind.rawValue)"), "agreed": agreed]))
        }
        if h.transport.alternatives.isEmpty && !h.transport.hasVehicle { lines.append(b.line("plan.transport.none")) }
        lines.append(contentsOf: continuityDestinationLines(b, h))
        return lines
    }

    private static func waterLines(_ b: Builder, _ h: HouseholdProfile) -> [PlanLine] {
        let target = PlanningMeasurements.waterText(gallons: WaterTarget.storageTargetGallons(people: h.people.count, days: 3), countryCode: h.privateLocation?.countryCode, localizer: b.localizer)
        let stored = h.supplies.storedWaterGallons.confirmedValue.map { PlanningMeasurements.waterText(gallons: $0, countryCode: h.privateLocation?.countryCode, localizer: b.localizer) }
            ?? b.localizer.text("plan.water.storedUnknown")
        var lines = [b.line("plan.water.target", ["people": "\(h.people.count)", "targetGallons": target.text, "storedGallons": stored.text], sources: ["S26"], composed: [target, stored])]
        if !h.pets.isEmpty { lines.append(b.line("plan.water.pets", sources: ["S26"])) }
        return lines
    }

    /// Current routes from the recorded scenario stage, one per person. Historical paths are not revived.
    private static func routeLines(_ b: Builder, _ routes: [RouteResult], _ home: HomeModel, _ h: HouseholdProfile) -> [PlanLine] {
        var lines: [PlanLine] = []
        var seen = Set<String>()
        for route in routes {
            let dedupe = "\(route.request.personID ?? "-")|\(route.request.startSpaceID)|\(route.request.mobility.requiresStepFree)|\(route.request.purpose?.rawValue ?? "outdoorEgress")"
            guard seen.insert(dedupe).inserted else { continue }
            let start = home.space(route.request.startSpaceID)?.label ?? b.l("plan.route.unknownRoom")
            let person = route.request.personID.flatMap { id in h.people.first { $0.id == id }?.localizedLabel(b.localizer) }
            let who = person.map { "\($0) — \(start)" } ?? start
            if let primary = route.primary {
                let outdoor = route.request.purpose == nil || route.request.purpose == .outdoorEgress
                lines.append(b.line("plan.route.from", ["start": who, "steps": steps(b, primary, home, outdoor: outdoor)], sources: [outdoor ? "S19" : "S22"]))
                guard outdoor else { continue }
                switch route.alternativeStatus {
                case .independent:
                    if let alt = route.alternative {
                        lines.append(b.line("plan.route.alt", ["start": who, "steps": steps(b, alt, home)], sources: ["S19"]))
                    }
                case .sharesChokepoint:
                    let choke = route.sharedChokepoints.first.map { elementLabel(b, $0, home) } ?? b.l("plan.route.unknownRoom")
                    lines.append(b.line("plan.route.altShared", ["start": who, "chokepoint": choke], style: .caveat))
                case .none:
                    lines.append(b.line("plan.route.altNone", ["start": who], style: .caveat))
                }
            } else {
                let reason = b.l("plan.route.reason.\((route.noRouteReason ?? .incompleteConnectivity).rawValue)")
                lines.append(b.line("plan.route.none", ["start": who, "reason": reason], style: .caveat))
            }
        }
        return lines
    }

    /// Human label for a space or portal ID; never prints a raw identifier.
    static func elementLabel(_ b: Builder, _ id: String, _ home: HomeModel) -> String {
        if let s = home.space(id) { return s.label }
        if let p = home.portal(id) {
            func name(_ d: PortalDestination) -> String {
                switch d {
                case .space(let sid): home.space(sid)?.label ?? b.l("plan.route.unknownRoom")
                case .exterior: b.l("plan.route.outside")
                case .commonArea, .unknown: b.l("plan.route.unknownRoom")
                }
            }
            return b.l("plan.route.door", ["a": name(p.sideA), "b": name(p.sideB)])
        }
        return b.l("plan.route.unknownRoom")
    }

    private static func steps(_ b: Builder, _ path: RoutePath, _ home: HomeModel, outdoor: Bool = true) -> String {
        (path.spaceSequence.map { home.space($0)?.label ?? b.l("plan.route.unknownRoom") } + (outdoor ? [b.l("plan.route.outside")] : []))
            .joined(separator: " → ")
    }

    static func formatNumber(_ v: Double, locale: String = "en_US_POSIX") -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func displayDate(_ date: Date, locale: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func isoDay(_ d: Date, _ timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = timeZone
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

        func line(_ key: String, _ values: [String: String] = [:], style: PlanLineStyle = .normal, sources: [String] = [], composed: [LocalizedText] = []) -> PlanLine {
            for value in composed { track(value) }
            let t = track(localizer.text(key, values))
            sourceIDs.append(contentsOf: sources)
            return PlanLine(text: t.text, style: style, key: key, resolvedLocale: t.resolvedLocale,
                            isFallback: t.isFallback || composed.contains(where: \.isFallback), isDraftTranslation: t.needsDraftLabel || composed.contains(where: \.needsDraftLabel), sourceIDs: sources,
                            unfilledPlaceholders: Array(Set(t.unfilledPlaceholders + composed.flatMap(\.unfilledPlaceholders))).sorted())
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
