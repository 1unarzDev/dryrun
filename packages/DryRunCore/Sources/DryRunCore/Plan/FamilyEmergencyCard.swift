import Foundation

/// Intentional export selections. Private notes and clinical fields are independent choices.
public struct FamilyCardSelection: Codable, Sendable, Hashable {
    public var includeCriticalInformation: Bool
    public var includeMedication: Bool
    public var includeResponderInstructions: Bool
    public var includeContacts: Bool
    public init(includeCriticalInformation: Bool = false, includeMedication: Bool = false,
                includeResponderInstructions: Bool = false, includeContacts: Bool = true) {
        self.includeCriticalInformation = includeCriticalInformation; self.includeMedication = includeMedication
        self.includeResponderInstructions = includeResponderInstructions; self.includeContacts = includeContacts
    }
}

public enum FamilyEmergencyCardBuilder {
    public static func page(household h: HouseholdProfile, savedPlaces: [SavedPlace] = [], localizer l: Localizer,
                            selection: FamilyCardSelection = FamilyCardSelection()) -> PlanPage {
        func line(_ text: String, style: PlanLineStyle = .normal, sources: [String] = []) -> PlanLine {
            PlanLine(text: text, style: style, key: "family.recorded", resolvedLocale: l.locale,
                     isFallback: false, isDraftTranslation: false, sourceIDs: sources)
        }
        func section(_ id: String, _ heading: String, _ lines: [PlanLine], critical: Bool = false) -> PlanSection {
            PlanSection(id: id, heading: l(heading), lines: lines, isSafetyCritical: critical)
        }
        var identity = [line(h.displayName)]
        if h.isFictional { identity.append(line(l("family.example"), style: .caveat)) }
        identity.append(line(h.privateLocation?.addressLine ?? l("family.addressMissing")))
        if let unit = h.privateLocation?.unit, !unit.isEmpty { identity.append(line(unit)) }
        var sections = [section("identity", "family.identity", identity)]
        var critical: [PlanLine] = []
        var instructionContinuations: [PlanLine] = []
        for p in h.people {
            var details: [String] = []
            let info = p.emergencyInformation
            if selection.includeCriticalInformation {
                if let value = info?.severeAllergies, !value.isEmpty { details.append(l("family.allergies") + ": " + value) }
                if let value = info?.criticalConditions, !value.isEmpty { details.append(l("family.conditions") + ": " + value) }
                details += p.needs.map { l("common.need.\($0.rawValue)") }
                if let note = p.communicationNotes, !note.isEmpty { details.append(note) }
            }
            details += h.equipment.filter {
                $0.personID == p.id && $0.isEssential && ($0.purpose == .refrigeratedMedication ? selection.includeMedication : selection.includeCriticalInformation)
            }.map { $0.localizedLabel(l) }
            if selection.includeMedication, let value = info?.essentialMedication, !value.isEmpty { details.append(l("family.medication") + ": " + value) }
            if selection.includeResponderInstructions, let value = info?.responderInstructions, !value.isEmpty {
                if value.count > 600 {
                    // Keep contacts and meetups on the main card. Never summarize or rewrite a clinical note.
                    details.append(l("family.instructionsContinued"))
                    instructionContinuations.append(line(p.localizedLabel(l) + ": " + value))
                } else { details.append(value) }
            }
            critical.append(line((p.alias.isEmpty ? l(p.isSelf == true ? "family.you" : "ui.person") : p.alias) + ": " + (details.isEmpty ? l("family.notProvidedSelected") : details.joined(separator: "; "))))
        }
        sections.append(section("critical", "family.critical", critical.isEmpty ? [line(l("family.notProvidedSelected"))] : critical, critical: true))
        if selection.includeContacts {
            let contacts = h.contacts.map { c in
                let role = c.role == .other ? nil : l("ui.contact.role.\(c.role.rawValue)")
                return line([c.alias, c.relationship, role, c.phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") + (c.hasUsablePhone ? "" : " — " + l("family.phoneMissing")), style: .contact)
            }
            sections.append(section("contacts", "family.contacts", contacts.isEmpty ? [line(l("family.contactMissing"))] : contacts, critical: true))
        }
        for purpose in [SavedPlacePurpose.outsideMeetingPoint, .backupMeetingPlace] {
            let places = savedPlaces.filter { $0.purpose == purpose }
            let lines = places.map { p in
                let coordinate = p.coordinate.map {
                    l("map.pin") + ": " + String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude)
                }
                return line([p.label, p.addressText, p.findingInstructions, coordinate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            }
            sections.append(section(purpose.rawValue, purpose == .outsideMeetingPoint ? "family.nearMeetup" : "family.backupMeetup", lines.isEmpty ? [line(l("family.meetupMissing"))] : lines))
        }
        // Supporting details follow the same intentional clinical selections as the critical section.
        // Only recorded facts are included: no estimated runtime, storage limit, or free-text notes.
        var continuity: [PlanLine] = []
        func appendSupply(_ id: String, subject: String, titleKey: String, source: String) {
            guard let fact = h.preparedness?.items[id] else { return }
            let available = fact.available.confirmedValue.map { l($0 ? "ui.yes" : "ui.no") } ?? l("ui.notSure")
            var details = [subject, l(titleKey), l("family.haveItem") + ": " + available]
            if !fact.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                details.append(l("family.locationOfItem") + ": " + fact.location)
            }
            continuity.append(line(details.joined(separator: " · "), sources: [source]))
        }
        if selection.includeMedication {
            for person in h.people {
                appendSupply("medication.person.\(person.id)", subject: person.localizedLabel(l), titleKey: "prep.medication.title", source: "S54")
            }
        }
        for eq in h.equipment {
            let person = eq.personID.flatMap { id in h.people.first { $0.id == id } }?.localizedLabel(l)
            let subject = [person, eq.localizedLabel(l)].compactMap { $0 }.joined(separator: " · ")
            if selection.includeMedication, eq.purpose == .refrigeratedMedication {
                appendSupply("medication.equipment.\(eq.id)", subject: subject, titleKey: "prep.medication.title", source: "S54")
            }
            if selection.includeCriticalInformation, eq.purpose != .refrigeratedMedication {
                appendSupply("equipmentSupplies.\(eq.id)", subject: subject, titleKey: "prep.equipmentSupplies.title", source: "S25")
            }
        }
        for eq in h.equipment where eq.isEssential {
            let selected = eq.purpose == .refrigeratedMedication ? selection.includeMedication : selection.includeCriticalInformation
            guard selected else { continue }
            let name = eq.localizedLabel(l)
            let person = eq.personID.flatMap { id in h.people.first { $0.id == id } }?.localizedLabel(l)
            let subject = [person, name].compactMap { $0 }.joined(separator: " · ")
            if eq.requiresElectricalPower {
                let backups = OutageCardBuilder.compatibleBackups(for: eq, in: h)
                let backupDetails = backups.isEmpty ? [l("card.backup.none")] : backups.map {
                    l($0.setupConfirmed.confirmedValue == true ? "card.backup.tested" : "card.backup.notTested", ["backup": $0.localizedLabel(l)])
                }
                let runtime = eq.documentedBackupRuntimeHours.confirmedValue.map {
                    l("plan.equipment.runtimeKnown", ["hours": PlanBuilder.formatNumber($0)])
                } ?? l("plan.equipment.runtimeUnknown")
                continuity.append(line(subject + ": " + (backupDetails + [l("card.backup.runtime", ["runtime": runtime])]).joined(separator: " "), sources: ["S25"]))
            }
            if eq.requiresColdStorage {
                let recorded = eq.storageInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
                let instructions = recorded?.isEmpty == false ? recorded! : l("card.gap.storageInstructionsUnknown")
                let status = l(eq.storagePlanConfirmed?.confirmedValue == true ? "family.storageConfirmed" : "card.gap.storagePlanUnconfirmed")
                continuity.append(line(subject + ": " + l("family.storageInstructions") + ": " + instructions + " · " + status, sources: ["S54"]))
            }
        }
        if selection.includeCriticalInformation {
            for person in h.people {
                if let helperID = person.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }) {
                    continuity.append(line(l("plan.person.helper", ["helper": helper.localizedLabel(l), "alias": person.localizedLabel(l)]), sources: ["S19"]))
                }
            }
        }
        for vehicle in h.transport.vehicles {
            continuity.append(line(l("plan.transport.vehicle", ["seats": String(vehicle.seats)]), sources: ["S52"]))
        }
        for alternative in h.transport.alternatives {
            var details = l("plan.transport.alternative", ["kind": l("common.transport.\(alternative.kind.rawValue)"), "agreed": l(alternative.agreed.confirmedValue == true ? "plan.transport.agreed" : "plan.transport.notAgreed")])
            if selection.includeContacts, let contactID = alternative.contactID, let contact = h.contacts.first(where: { $0.id == contactID }) {
                details += " · " + [contact.alias, contact.phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            }
            continuity.append(line(details, sources: ["S52"]))
        }
        for id in ["water", "food", "firstAid", "flashlight", "batteries", "sanitation", "pets", "extinguisher"] {
            let fact = h.preparedness?.items[id]
            let location = fact?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let availability = BaselinePreparedness.recordedSupplyAvailability(id, household: h)
            guard !location.isEmpty || availability != nil else { continue }
            let available = availability.map { l($0 ? "ui.yes" : "ui.no") } ?? l("ui.notSure")
            var details = [l("prep.\(id).title"), l("family.haveItem") + ": " + available]
            if !location.isEmpty { details.append(l("family.locationOfItem") + ": " + location) }
            if id == "water", let gallons = h.supplies.storedWaterGallons.confirmedValue, gallons.isFinite, gallons >= 0 {
                let usesGallons = h.privateLocation?.countryCode?.uppercased() == "US"
                details.append(l(usesGallons ? "ui.setup.water.gallons" : "family.waterLitres") + ": " + PlanBuilder.formatNumber(usesGallons ? gallons : gallons * 3.785411784))
            }
            continuity.append(line(details.joined(separator: " · "), sources: [id == "water" ? "S26" : "S53"]))
        }
        if !continuity.isEmpty { sections.append(section("continuity", "family.continuity", continuity)) }
        sections.append(section("review", "family.review", [line(h.preparedness?.reviewedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? l("family.reviewMissing"))]))
        if !instructionContinuations.isEmpty {
            sections.append(section("instruction-continuation", "family.instructions", instructionContinuations, critical: true))
        }
        return PlanPage(id: "family-card", kind: .essentials, title: l("family.title"), sections: sections)
    }
}
