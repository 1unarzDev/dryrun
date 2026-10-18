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
                            selection: FamilyCardSelection = FamilyCardSelection(),
                            timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> PlanPage {
        page(household: h, savedPlaces: savedPlaces, builder: PlanBuilder.Builder(l: l), selection: selection, timeZone: timeZone)
    }

    static func page(household h: HouseholdProfile, savedPlaces: [SavedPlace], builder b: PlanBuilder.Builder,
                     selection: FamilyCardSelection, timeZone: TimeZone) -> PlanPage {
        let l = b.localizer
        var pending: [LocalizedText] = []
        func localized(_ key: String, _ values: [String: String] = [:]) -> String {
            let text = b.track(l.text(key, values)); pending.append(text); return text.text
        }
        func displayLabel(_ person: Person) -> String {
            person.alias.isEmpty ? localized(person.isSelf == true ? "family.you" : "ui.person") : person.alias
        }
        func displayLabel(_ equipment: PoweredEquipment) -> String {
            equipment.label.isEmpty ? localized("equipment.\(equipment.purpose.rawValue)") : equipment.label
        }
        func displayLabel(_ backup: BackupPowerSource) -> String {
            backup.label.isEmpty ? localized("enum.\(backup.kind.rawValue)") : backup.label
        }
        func line(_ text: String, style: PlanLineStyle = .normal, sources: [String] = [], parts: PlanLineParts? = nil) -> PlanLine {
            let translated = pending; pending.removeAll()
            b.sourceIDs.append(contentsOf: sources)
            return PlanLine(text: text, style: style, key: "family.recorded", resolvedLocale: l.locale,
                            isFallback: translated.contains(where: \.isFallback),
                            isDraftTranslation: translated.contains(where: \.needsDraftLabel), sourceIDs: sources,
                            unfilledPlaceholders: Array(Set(translated.flatMap(\.unfilledPlaceholders))).sorted(),
                            parts: parts)
        }
        func section(_ id: String, _ heading: String, _ lines: [PlanLine], critical: Bool = false) -> PlanSection {
            PlanSection(id: id, heading: b.l(heading), lines: lines, isSafetyCritical: critical)
        }
        var identity = [line(h.displayName, parts: PlanLineParts(subject: h.displayName))]
        if h.isFictional { identity.append(line(localized("family.example"), style: .caveat)) }
        let address = h.privateLocation?.addressLine
        identity.append(line(address ?? localized("family.addressMissing"),
                             parts: PlanLineParts(fields: [PlanField(value: address ?? localized("family.addressMissing"))], isMissing: address == nil)))
        if let unit = h.privateLocation?.unit, !unit.isEmpty { identity.append(line(unit)) }
        var sections = [section("identity", "family.identity", identity)]
        var critical: [PlanLine] = []
        var instructionContinuations: [PlanLine] = []
        for p in h.people {
            var details: [String] = []
            var fields: [PlanField] = []
            var longInstruction: String?
            let info = p.emergencyInformation
            if selection.includeCriticalInformation {
                if let value = info?.severeAllergies, !value.isEmpty {
                    let label = localized("family.allergies"); details.append(label + ": " + value); fields.append(PlanField(label: label, value: value))
                }
                if let value = info?.criticalConditions, !value.isEmpty {
                    let label = localized("family.conditions"); details.append(label + ": " + value); fields.append(PlanField(label: label, value: value))
                }
                for need in p.needs {
                    let value = localized("common.need.\(need.rawValue)"); details.append(value); fields.append(PlanField(value: value))
                }
                if let note = p.communicationNotes, !note.isEmpty { details.append(note); fields.append(PlanField(value: note)) }
            }
            for eq in h.equipment where eq.personID == p.id && eq.isEssential
                && (eq.purpose == .refrigeratedMedication ? selection.includeMedication : selection.includeCriticalInformation) {
                let value = displayLabel(eq); details.append(value); fields.append(PlanField(value: value))
            }
            if selection.includeMedication, let value = info?.essentialMedication, !value.isEmpty {
                let label = localized("family.medication"); details.append(label + ": " + value); fields.append(PlanField(label: label, value: value))
            }
            if selection.includeResponderInstructions, let value = info?.responderInstructions, !value.isEmpty {
                if value.count > 600 {
                    // Keep contacts and meetups on the main card. Never summarize or rewrite a clinical note.
                    let pointer = localized("family.instructionsContinued")
                    details.append(pointer); fields.append(PlanField(value: pointer))
                    longInstruction = value
                } else { details.append(value); fields.append(PlanField(value: value)) }
            }
            let name = p.alias.isEmpty ? localized(p.isSelf == true ? "family.you" : "ui.person") : p.alias
            let missing = localized("family.notProvidedSelected")
            critical.append(line(name + ": " + (details.isEmpty ? missing : details.joined(separator: "; ")),
                                 parts: PlanLineParts(subject: name, fields: details.isEmpty ? [PlanField(value: missing)] : fields, isMissing: details.isEmpty)))
            if let longInstruction {
                instructionContinuations.append(line(displayLabel(p) + ": " + longInstruction,
                                                     parts: PlanLineParts(subject: displayLabel(p), fields: [PlanField(value: longInstruction)])))
            }
        }
        let noCritical = localized("family.notProvidedSelected")
        sections.append(section("critical", "family.critical", critical.isEmpty ? [line(noCritical, parts: PlanLineParts(fields: [PlanField(value: noCritical)], isMissing: true))] : critical, critical: true))
        if selection.includeContacts {
            let contacts = h.contacts.map { c in
                let role = c.role == .other ? nil : localized("ui.contact.role.\(c.role.rawValue)")
                let phoneMissing = c.hasUsablePhone ? nil : localized("family.phoneMissing")
                let detail = [c.relationship, role].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return line([c.alias, c.relationship, role, c.phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") + (phoneMissing.map { " — " + $0 } ?? ""), style: .contact,
                            parts: PlanLineParts(subject: c.alias, detail: detail.isEmpty ? nil : detail,
                                                 fields: phoneMissing.map { [PlanField(value: $0)] } ?? [],
                                                 phone: c.hasUsablePhone ? c.phone : nil, isMissing: phoneMissing != nil))
            }
            let noContact = localized("family.contactMissing")
            sections.append(section("contacts", "family.contacts", contacts.isEmpty ? [line(noContact, parts: PlanLineParts(fields: [PlanField(value: noContact)], isMissing: true))] : contacts, critical: true))
        }
        for purpose in [SavedPlacePurpose.outsideMeetingPoint, .backupMeetingPlace] {
            let places = savedPlaces.filter { $0.purpose == purpose }
            let lines = places.map { p in
                let pinLabel = localized("map.pin")
                let pinValue = p.coordinate.map { String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude) }
                let coordinate = pinValue.map { pinLabel + ": " + $0 }
                var fields: [PlanField] = []
                if let address = p.addressText, !address.isEmpty { fields.append(PlanField(value: address)) }
                if let instructions = p.findingInstructions, !instructions.isEmpty { fields.append(PlanField(value: instructions)) }
                if let pinValue { fields.append(PlanField(label: pinLabel, value: pinValue)) }
                return line([p.label, p.addressText, p.findingInstructions, coordinate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                            parts: PlanLineParts(subject: p.label, fields: fields))
            }
            let noMeetup = localized("family.meetupMissing")
            sections.append(section(purpose.rawValue, purpose == .outsideMeetingPoint ? "family.nearMeetup" : "family.backupMeetup", lines.isEmpty ? [line(noMeetup, parts: PlanLineParts(fields: [PlanField(value: noMeetup)], isMissing: true))] : lines))
        }
        // Supporting details follow the same intentional clinical selections as the critical section.
        // Only recorded facts are included: no estimated runtime, storage limit, or free-text notes.
        var continuity: [PlanLine] = []
        func equipmentSubject(_ equipment: PoweredEquipment) -> String {
            let person = equipment.personID.flatMap { id in h.people.first { $0.id == id } }.map { displayLabel($0) }
            return [person, displayLabel(equipment)].compactMap { $0 }.joined(separator: " · ")
        }
        func appendSupply(_ id: String, subject: @autoclosure () -> String, titleKey: String, source: String) {
            guard let fact = h.preparedness?.items[id] else { return }
            let available = fact.available.confirmedValue.map { localized($0 ? "ui.yes" : "ui.no") } ?? localized("ui.notSure")
            var details = [subject(), localized(titleKey), localized("family.haveItem") + ": " + available]
            if !fact.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                details.append(localized("family.locationOfItem") + ": " + fact.location)
            }
            continuity.append(line(details.joined(separator: " · "), sources: [source]))
        }
        if selection.includeMedication {
            for person in h.people {
                appendSupply("medication.person.\(person.id)", subject: displayLabel(person), titleKey: "prep.medication.title", source: "S54")
            }
        }
        for eq in h.equipment {
            if selection.includeMedication, eq.purpose == .refrigeratedMedication {
                appendSupply("medication.equipment.\(eq.id)", subject: equipmentSubject(eq), titleKey: "prep.medication.title", source: "S54")
            }
            if selection.includeCriticalInformation, eq.purpose != .refrigeratedMedication {
                appendSupply("equipmentSupplies.\(eq.id)", subject: equipmentSubject(eq), titleKey: "prep.equipmentSupplies.title", source: "S25")
            }
        }
        for eq in h.equipment where eq.isEssential {
            let selected = eq.purpose == .refrigeratedMedication ? selection.includeMedication : selection.includeCriticalInformation
            guard selected else { continue }
            if eq.requiresElectricalPower {
                let subject = equipmentSubject(eq)
                let backups = OutageCardBuilder.compatibleBackups(for: eq, in: h)
                var backupDetails = backups.isEmpty ? [localized("card.backup.none")] : backups.map { backup in
                    let status = localized(backup.setupConfirmed.confirmedValue == true ? "card.backup.tested" : "card.backup.notTested", ["backup": displayLabel(backup)])
                    let usability = BackupAllocator.usability(backup, energyRemaining: backup.usableEnergyWh.confirmedValue)
                    return usability == .usable ? status : status + " " + localized("card.backup.prerequisites", ["reason": localized("reason.\(usability.rawValue)")])
                }
                if !backups.isEmpty, let assignment = MedicalBackupReadiness.assignment(for: eq, in: h), assignment.state != .operational,
                   !backups.contains(where: { BackupAllocator.usability($0, energyRemaining: $0.usableEnergyWh.confirmedValue).rawValue == assignment.reason }) {
                    backupDetails.append(localized("card.backup.prerequisites", ["reason": localized("reason.\(assignment.reason)")]))
                }
                let runtime = eq.documentedBackupRuntimeHours.confirmedValue.map {
                    localized("plan.equipment.runtimeKnown", ["hours": PlanBuilder.formatNumber($0, locale: l.locale)])
                } ?? localized("plan.equipment.runtimeUnknown")
                continuity.append(line(subject + ": " + (backupDetails + [localized("card.backup.runtime", ["runtime": runtime])]).joined(separator: " "), sources: ["S25"]))
            }
            if eq.requiresColdStorage {
                let subject = equipmentSubject(eq)
                let recorded = eq.storageInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
                let instructions = recorded?.isEmpty == false ? recorded! : localized("card.gap.storageInstructionsUnknown")
                let status = localized(eq.storagePlanConfirmed?.confirmedValue == true ? "family.storageConfirmed" : "card.gap.storagePlanUnconfirmed")
                continuity.append(line(subject + ": " + localized("family.storageInstructions") + ": " + instructions + " · " + status, sources: ["S54"]))
            }
        }
        if selection.includeCriticalInformation {
            for person in h.people {
                if let helperID = person.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }) {
                    continuity.append(line(localized("plan.person.helper", ["helper": displayLabel(helper), "alias": displayLabel(person)]), sources: ["S19"]))
                }
            }
        }
        for vehicle in h.transport.vehicles {
            continuity.append(line(localized("plan.transport.vehicle", ["seats": String(vehicle.seats)]), sources: ["S52"]))
        }
        for alternative in h.transport.alternatives {
            var details = localized("plan.transport.alternative", ["kind": localized("common.transport.\(alternative.kind.rawValue)"), "agreed": localized(alternative.agreed.confirmedValue == true ? "plan.transport.agreed" : "plan.transport.notAgreed")])
            if selection.includeContacts, let contactID = alternative.contactID, let contact = h.contacts.first(where: { $0.id == contactID }) {
                details += " · " + [contact.alias, contact.phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            }
            continuity.append(line(details, sources: ["S52"]))
        }
        continuity.append(contentsOf: PlanBuilder.continuityDestinationLines(b, h))
        for id in ["water", "food", "firstAid", "flashlight", "batteries", "sanitation", "pets", "extinguisher"] {
            let fact = h.preparedness?.items[id]
            let location = fact?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let availability = BaselinePreparedness.recordedSupplyAvailability(id, household: h)
            guard !location.isEmpty || availability != nil else { continue }
            let available = availability.map { localized($0 ? "ui.yes" : "ui.no") } ?? localized("ui.notSure")
            var details = [localized("prep.\(id).title"), localized("family.haveItem") + ": " + available]
            if !location.isEmpty { details.append(localized("family.locationOfItem") + ": " + location) }
            if id == "water", let gallons = h.supplies.storedWaterGallons.confirmedValue, gallons.isFinite, gallons >= 0 {
                let usesGallons = h.privateLocation?.countryCode?.uppercased() == "US"
                details.append(localized(usesGallons ? "ui.setup.water.gallons" : "family.waterLitres") + ": " + PlanBuilder.formatNumber(usesGallons ? gallons : gallons * 3.785411784, locale: l.locale))
            }
            continuity.append(line(details.joined(separator: " · "), sources: [id == "water" ? "S26" : "S53"]))
        }
        if !continuity.isEmpty { sections.append(section("continuity", "family.continuity", continuity)) }
        let reviewed = h.preparedness?.reviewedAt.map { PlanBuilder.displayDate($0, locale: l.locale, timeZone: timeZone) }
        let reviewText = reviewed ?? localized("family.reviewMissing")
        sections.append(section("review", "family.review", [line(reviewText, parts: PlanLineParts(fields: [PlanField(value: reviewText)], isMissing: reviewed == nil))]))
        if !instructionContinuations.isEmpty {
            sections.append(section("instruction-continuation", "family.instructions", instructionContinuations, critical: true))
        }
        return PlanPage(id: "family-card", kind: .essentials, title: localized("family.title"), sections: sections)
    }
}
