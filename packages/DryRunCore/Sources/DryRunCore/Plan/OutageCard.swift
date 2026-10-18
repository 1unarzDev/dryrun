import Foundation

/// What is still missing before a device's outage card is dependable. Each gap maps to one thing the household can
/// do or record; none is a score.
public enum OutageCardGap: String, Codable, Sendable, Hashable, CaseIterable {
    /// No backup source is recorded as working with this device.
    case storageInstructionsUnknown
    case storagePlanUnconfirmed
    case noCompatibleBackup
    /// A compatible backup is recorded, but nobody has set it up and tested it.
    case backupNotTested
    /// Source prerequisites or the allocation to this device remain unresolved.
    case backupPrerequisitesUnconfirmed
    /// The runtime on backup is not documented (manufacturer or care plan). Dry Run never estimates it.
    case runtimeUnknown
    /// No supplier, care team, or utility medical registry contact is recorded.
    case noCareContact
    /// No out-of-area contact is recorded.
    case noOutOfAreaContact
    /// No place to go has been confirmed with its host.
    case noConfirmedDestination
}

/// Builds the medical power-outage card: one page per essential powered device, made only from facts the household
/// recorded. It never estimates how long someone is safe without power and never invents a runtime; a missing fact is
/// printed as missing. The result is a `PlanDocument`, so the same viewer, PDF renderer, and validator apply.
public enum OutageCardBuilder {
    /// Essential devices that get a card, in household order.
    public static func devices(in h: HouseholdProfile) -> [PoweredEquipment] {
        h.equipment.filter(\.isEssential)
    }

    /// Backups recorded as compatible with `eq` that exist in the household.
    public static func compatibleBackups(for eq: PoweredEquipment, in h: HouseholdProfile) -> [BackupPowerSource] {
        eq.compatibleBackupIDs.compactMap { id in h.backupPower.first { $0.id == id } }
    }

    public static func careContacts(in h: HouseholdProfile) -> [HouseholdContact] {
        h.contacts.filter { ($0.role == .careProvider || $0.role == .utilityMedicalRegistry) && $0.hasUsablePhone }
    }

    public static func confirmedDestinations(in h: HouseholdProfile) -> [RelocationDestination] {
        h.transport.destinations.filter { $0.conditionsConfirmed.confirmedValue == true }
    }

    public static func gaps(for eq: PoweredEquipment, in h: HouseholdProfile) -> [OutageCardGap] {
        var out: [OutageCardGap] = []
        let backups = compatibleBackups(for: eq, in: h)
        if eq.requiresElectricalPower {
        if backups.isEmpty { out.append(.noCompatibleBackup) }
        else if !backups.contains(where: { $0.setupConfirmed.confirmedValue == true }) { out.append(.backupNotTested) }
        else if MedicalBackupReadiness.assignment(for: eq, in: h)?.state != .operational { out.append(.backupPrerequisitesUnconfirmed) }
        if !MedicalBackupReadiness.hasRecordedRuntime(eq) { out.append(.runtimeUnknown) }
        }
        if eq.requiresColdStorage {
            if (eq.storageInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.storageInstructionsUnknown) }
            if eq.storagePlanConfirmed?.confirmedValue != true { out.append(.storagePlanUnconfirmed) }
        }
        if careContacts(in: h).isEmpty { out.append(.noCareContact) }
        if !h.contacts.contains(where: { $0.role == .outOfAreaContact && $0.hasUsablePhone }) { out.append(.noOutOfAreaContact) }
        if confirmedDestinations(in: h).isEmpty { out.append(.noConfirmedDestination) }
        return out
    }

    public static func build(household h: HouseholdProfile, homeID: String, homeRevision: Int, localizer l: Localizer,
                             resources: [PublicResource], contentVersion: String, generatedAt: Date,
                             equipmentIDs: [String]? = nil, options: PlanBuilder.Options = PlanBuilder.Options()) -> PlanDocument {
        let b = PlanBuilder.Builder(l: l)
        let chosen = devices(in: h).filter { equipmentIDs?.contains($0.id) ?? true }
        let pages = chosen.map { page(b, $0, h, resources, options) }
        return PlanDocument(
            schemaVersion: PlanDocument.schemaVersion, locale: l.locale, householdID: h.id,
            householdRevision: h.revision, homeID: homeID, homeRevision: homeRevision,
            contentVersion: contentVersion, generatedAt: generatedAt, reviewedAt: options.reviewedAt,
            scenarioIDs: [], includesPrivateNotes: options.includePrivateNotes, pages: pages,
            draftTranslationBanner: b.usedDraft ? PlanBuilder.draftBanner(l) : nil,
            fallbackNote: b.usedFallback ? l.text("plan.fallbackNote").text : nil,
            contentReviewBanner: l.text("plan.contentDraftBanner").text,
            footer: l.text("card.footer").text,
            sourceIDs: Array(Set(b.sourceIDs)).sorted())
    }

    private static func page(_ b: PlanBuilder.Builder, _ eq: PoweredEquipment, _ h: HouseholdProfile,
                             _ resources: [PublicResource], _ options: PlanBuilder.Options) -> PlanPage {
        let user = eq.personID.flatMap { id in h.people.first { $0.id == id } }
        let backups = compatibleBackups(for: eq, in: h)
        var sections: [PlanSection] = []

        // Who and what.
        var device = [user.map { b.line("card.device.usedBy", ["device": eq.localizedLabel(b.localizer), "person": $0.localizedLabel(b.localizer)]) }
                      ?? b.line("card.device.line", ["device": eq.localizedLabel(b.localizer)])]
        if eq.requiresColdStorage { device.append(b.line("card.device.needsRefrigeration")) }
        if let notes = eq.carePlanNotes, !notes.isEmpty, options.includePrivateNotes {
            device.append(PlanLine(text: notes, style: .normal, key: "private.carePlanNotes", resolvedLocale: b.localizer.locale,
                                   isFallback: false, isDraftTranslation: false, sourceIDs: []))
        }
        sections.append(b.section("device", "card.section.device", device, critical: false))

        // Backup power: only what the household recorded; never an estimate.
        if eq.requiresElectricalPower {
        var power: [PlanLine] = backups.flatMap { bk in
            var lines = [b.line(bk.setupConfirmed.confirmedValue == true ? "card.backup.tested" : "card.backup.notTested",
                   ["backup": bk.localizedLabel(b.localizer)], sources: ["S25"])]
            let usability = BackupAllocator.usability(bk, energyRemaining: bk.usableEnergyWh.confirmedValue)
            if usability != .usable {
                lines.append(b.line("card.backup.prerequisites", ["reason": b.l("reason.\(usability.rawValue)")], style: .caveat, sources: ["S25"]))
            }
            return lines
        }
        if backups.isEmpty { power.append(b.line("card.backup.none", sources: ["S25"])) }
        if !backups.isEmpty, let assignment = MedicalBackupReadiness.assignment(for: eq, in: h), assignment.state != .operational,
           !backups.contains(where: { BackupAllocator.usability($0, energyRemaining: $0.usableEnergyWh.confirmedValue).rawValue == assignment.reason }) {
            power.append(b.line("card.backup.prerequisites", ["reason": b.l("reason.\(assignment.reason)")], style: .caveat, sources: ["S25"]))
        }
        let runtime = eq.documentedBackupRuntimeHours.confirmedValue.map {
            b.l("plan.equipment.runtimeKnown", ["hours": PlanBuilder.formatNumber($0, locale: b.localizer.locale)])
        } ?? b.l("plan.equipment.runtimeUnknown")
        power.append(b.line("card.backup.runtime", ["runtime": runtime], sources: ["S25"]))
        sections.append(b.section("backup", "card.section.backup", power, critical: true))

        }
        if eq.requiresColdStorage {
            let storage = [PlanLine(text: eq.storageInstructions ?? b.l("family.providerPrompt"), style: .normal, key: "private.storageInstructions", resolvedLocale: b.localizer.locale, isFallback: false, isDraftTranslation: false, sourceIDs: ["S54"])]
            sections.append(b.section("storage", "family.storageInstructions", storage, critical: true))
        }
        // First steps when the power goes out.
        var steps: [PlanLine] = []
        if h.privateLocation?.countryCode?.uppercased() == "US" || (h.privateLocation?.countryCode == nil && PublicDataPolicy.isAllowedRegionID(h.regionID)) { steps.append(b.line("plan.help.911", style: .contact)) }
        if let assignment = MedicalBackupReadiness.assignment(for: eq, in: h), assignment.state == .operational,
           let selected = backups.first(where: { $0.id == assignment.sourceID }) {
            steps.append(b.line("card.steps.switchToBackup", ["device": eq.localizedLabel(b.localizer), "backup": selected.localizedLabel(b.localizer)]))
        }
        let care = careContacts(in: h)
        if let first = care.first {
            steps.append(b.line("card.steps.callCare", ["contact": first.alias]))
        }
        if let helperID = user?.helperPersonID, let helper = h.people.first(where: { $0.id == helperID }), let user {
            steps.append(b.line("plan.person.helper", ["helper": helper.localizedLabel(b.localizer), "alias": user.localizedLabel(b.localizer)]))
        }
        sections.append(b.section("steps", "card.section.steps", steps, critical: true))

        // People to call: care team first, then out-of-area contacts.
        var people: [PlanLine] = (care + h.contacts.filter { $0.role == .outOfAreaContact && $0.hasUsablePhone }).map { c in
            c.phone.map { b.line("plan.contact.line", ["alias": c.alias, "phone": $0], style: .contact) }
                ?? b.line("plan.contact.noPhone", ["alias": c.alias])
        }
        if people.isEmpty { people.append(b.line("plan.contact.none")) }
        sections.append(b.section("contacts", "card.section.contacts", people, critical: true))

        // Where to go: confirmed with the host only. A public site is never assumed to be open.
        let destinations = confirmedDestinations(in: h)
        let goTo: [PlanLine] = destinations.isEmpty
            ? [b.line("card.goTo.none")]
            : destinations.map { b.line("card.goTo.confirmed", ["place": $0.label]) }
        sections.append(b.section("goTo", "card.section.goTo", goTo, critical: false))

        sections.append(b.section("help", "plan.section.help", PlanBuilder.helpLines(b, resources, countryCode: h.privateLocation?.countryCode), critical: true))

        let gapLines = gaps(for: eq, in: h).map { b.line("card.gap.\($0.rawValue)", style: .caveat) }
        if !gapLines.isEmpty { sections.append(b.section("gaps", "card.section.gaps", gapLines, critical: false)) }

        return PlanPage(id: "card-\(eq.id)", kind: .outageCard(eq.id),
                        title: b.l("card.title", ["device": eq.localizedLabel(b.localizer)]), sections: sections)
    }
}
