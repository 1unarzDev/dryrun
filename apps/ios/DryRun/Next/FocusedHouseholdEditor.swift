import SwiftUI
import DryRunCore

/// One save boundary shared by Prepare, the card, and individual factual tasks.
struct FocusedHouseholdEditor: View {
    enum Focus { case family, contacts, supplies, transport, backups, review, preparation(String) }
    let focus: Focus
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HouseholdProfile?
    @State private var saving = false
    @State private var saveFailed = false

    var body: some View {
        let l = model.localizer
        Form {
            if draft != nil {
                switch focus {
                case .family: familyFields
                case .contacts: contactFields
                case .supplies: supplyFields
                case .transport: transportFields
                case .backups: backupFields
                case .review: reviewFields
                case .preparation(let id): preparationFields(id)
                }
            }
            if saveFailed { Text(model.lastError ?? l("ui.tryFailed")).foregroundStyle(Theme.caution) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(l("ui.save")) { save() }.disabled(saving).accessibilityIdentifier("focused.save")
            }
        }
        .onAppear {
            if draft == nil {
                draft = model.household
                if case .contacts = focus, draft?.contacts.isEmpty == true {
                    draft?.contacts.append(HouseholdContact(id: UUID().uuidString, role: .other, alias: ""))
                }
            }
        }
    }

    private var title: String {
        switch focus {
        case .family: model.localizer("family.edit")
        case .contacts: model.localizer("family.contacts")
        case .supplies: model.localizer("family.supplies")
        case .transport: model.localizer("ui.setup.gettingAround")
        case .backups: model.localizer("card.section.backup")
        case .review: model.localizer("prep.reviewCard.title")
        case .preparation(let id): model.localizer("prep.\(id).title")
        }
    }
    private func binding<T>(_ path: WritableKeyPath<HouseholdProfile, T>) -> Binding<T> {
        Binding(get: { draft![keyPath: path] }, set: { draft![keyPath: path] = $0 })
    }
    private func info(_ index: Int, _ path: WritableKeyPath<PersonEmergencyInformation, String>) -> Binding<String> {
        Binding(get: { draft!.people[index].emergencyInformation?[keyPath: path] ?? "" }, set: { value in
            if draft!.people[index].emergencyInformation == nil { draft!.people[index].emergencyInformation = PersonEmergencyInformation() }
            draft!.people[index].emergencyInformation![keyPath: path] = value
        })
    }
    private var familyFields: some View {
        let l = model.localizer
        return Group {
            Section { TextField(l("family.identity"), text: binding(\.displayName)).accessibilityIdentifier("family.householdName") }
            ForEach(Array((draft?.people ?? []).indices), id: \.self) { i in
                Section(draft!.people[i].isSelf == true ? l("family.you") : draft!.people[i].alias) {
                    TextField(l("family.name"), text: binding(\.people[i].alias)).accessibilityIdentifier("family.personName.\(draft!.people[i].id)")
                    Picker(l("family.relationship"), selection: binding(\.people[i].relationship)) {
                        Text(l("family.unknown")).tag(FamilyRelationship?.none)
                        ForEach(FamilyRelationship.allCases, id: \.self) { relationship in
                            Text(l("relationship.\(relationship.rawValue)")).tag(Optional(relationship))
                        }
                    }
                    if draft!.people[i].relationship == .custom {
                        TextField(l("family.relationship"), text: Binding(get: { draft!.people[i].customRelationship ?? "" }, set: { draft!.people[i].customRelationship = $0 }))
                    }
                    Picker(l("family.age"), selection: binding(\.people[i].ageBand)) {
                        ForEach(AgeBand.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: l)).tag($0) }
                    }
                    TextField(l("family.conditions"), text: info(i, \.criticalConditions), axis: .vertical)
                    TextField(l("family.allergies"), text: info(i, \.severeAllergies), axis: .vertical)
                    TextField(l("family.medication"), text: info(i, \.essentialMedication), axis: .vertical)
                    TextField(l("family.instructions"), text: info(i, \.responderInstructions), axis: .vertical)
                    ForEach(AssistanceNeed.allCases, id: \.self) { need in
                        Toggle(l("common.need.\(need.rawValue)"), isOn: Binding(get: { draft!.people[i].needs.contains(need) }, set: { on in
                            draft!.people[i].needs.removeAll { $0 == need }
                            if on { draft!.people[i].needs.append(need) }
                        }))
                    }
                    TextField(l("common.need.communicationSupport"), text: Binding(get: { draft!.people[i].communicationNotes ?? "" }, set: { draft!.people[i].communicationNotes = $0 }), axis: .vertical)
                    Picker(l("family.startRoom"), selection: binding(\.people[i].sleepingSpaceID)) {
                        Text(l("family.unknown")).tag(String?.none)
                        ForEach(model.home?.spaces ?? []) { Text($0.label).tag(Optional($0.id)) }
                    }
                    Picker(l("family.helper"), selection: binding(\.people[i].helperPersonID)) {
                        Text(l("family.unknown")).tag(String?.none)
                        ForEach(draft!.people.filter { $0.id != draft!.people[i].id }) { Text($0.localizedLabel(l)).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                Button(l("family.add"), systemImage: "person.badge.plus") {
                    draft!.people.append(Person(id: UUID().uuidString, alias: "", ageBand: .unknown))
                }.accessibilityIdentifier("family.addPerson")
            }
            preparationFields("reconnect")
            Section(l("family.review")) {
                Toggle(l("family.reviewedTogether"), isOn: Binding(get: { draft?.preparedness?.jointlyReviewedAt != nil }, set: { reviewed in
                    if draft?.preparedness == nil { draft?.preparedness = PreparednessRecord() }
                    draft?.preparedness?.jointlyReviewedAt = reviewed ? Date() : nil
                }))
                if let date = draft?.preparedness?.jointlyReviewedAt { Text(date, style: .date) }
            }
        }
    }
    private var contactFields: some View {
        let l = model.localizer
        return Group {
            ForEach(binding(\.contacts)) { $contact in
                Section {
                    TextField(l("ui.contact.name"), text: $contact.alias).accessibilityIdentifier("contacts.name.\(contact.id)")
                    TextField(l("family.relationship"), text: Binding(get: { contact.relationship ?? "" }, set: { contact.relationship = $0 }))
                    Picker(l("ui.contact.role"), selection: $contact.role) {
                        ForEach(ContactRole.allCases, id: \.self) { Text(l("ui.contact.role.\($0.rawValue)")).tag($0) }
                    }
                    TextField(l("ui.contact.phone"), text: Binding(get: { contact.phone ?? "" }, set: { contact.phone = $0 }))
                        .keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("contacts.phone.\(contact.id)")
                    if !contact.hasUsablePhone { Text(l("family.phoneMissing")).font(.caption).foregroundStyle(Theme.caution) }
                }
            }
            .onDelete { draft!.contacts.remove(atOffsets: $0) }
            Button(l("prep.contact.title"), systemImage: "plus") {
                draft!.contacts.append(HouseholdContact(id: UUID().uuidString, role: .other, alias: ""))
            }.accessibilityIdentifier("contacts.add")
        }
    }
    private var reviewFields: some View {
        let l = model.localizer
        return Group {
            if let draft {
                let page = FamilyEmergencyCardBuilder.page(household: draft, savedPlaces: model.savedPlaces.filter { $0.homeID == (model.home?.id ?? draft.stableHomeID) },
                    localizer: l, selection: .init(includeCriticalInformation: true, includeMedication: true, includeResponderInstructions: true))
                ForEach(page.sections) { section in
                    Section(section.heading) { ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in Text(line.text) } }
                }
            }
            Section {
                Button(l("family.reviewNow")) {
                    if draft?.preparedness == nil { draft?.preparedness = PreparednessRecord() }
                    draft?.preparedness?.reviewedAt = Date()
                }.accessibilityIdentifier("family.reviewNow")
                Text(l("prep.reviewCard.why")).font(.footnote)
            }
            ReviewReminderSection()
        }
    }
    private var supplyFields: some View {
        let l = model.localizer
        return Group {
            Section(l("prep.water.title")) {
                WaterStorageEvidenceRow(value: binding(\.supplies.storedWaterGallons), countryCode: draft?.privateLocation?.countryCode)
                Text(l("prep.water.why", ["target": String((draft?.people.count ?? 1) * 3), "litres": String(Int(Double((draft?.people.count ?? 1) * 3) * 3.78541))])).font(.footnote)
            }
            Section(l("family.supplies")) {
                NumberEvidenceRow(title: l("ui.setup.food.days"), value: binding(\.supplies.shelfStableFoodDays), unit: "d")
                NumberEvidenceRow(title: l("family.powerBankCharges"), value: binding(\.communications.powerBankCharges), unit: "charges")
                TriStateRow(title: l("action.act.comms.weather-radio.title"), value: binding(\.communications.batteryOrCrankRadio))
                TriStateRow(title: l("family.cooler"), value: binding(\.supplies.coolerAndIcePacks))
            }
            ForEach(BaselinePreparedness.definitions) { preparationFields($0.id) }
            if !(draft?.pets.isEmpty ?? true) { preparationFields("pets") }
        }
    }
    private var backupFields: some View {
        let l = model.localizer
        return Group {
            ForEach(binding(\.backupPower)) { $backup in
                Section {
                    BackupEditorFields(backup: $backup, onKindChanged: { draft?.invalidateBackupCompatibility(for: $0) })
                    NumberEvidenceRow(title: l("family.energy"), value: $backup.usableEnergyWh, unit: "Wh")
                    NumberEvidenceRow(title: l("family.output"), value: $backup.continuousOutputW, unit: "W")
                }
            }
            Button(l("ui.medical.addBackup"), systemImage: "plus") {
                draft!.backupPower.append(BackupPowerSource(id: UUID().uuidString, kind: .portableBatteryStation, label: ""))
            }
            Text(l("ui.medical.backupFooter")).font(.footnote)
        }
    }
    private var transportFields: some View {
        let l = model.localizer
        return Group {
            Section(l("ui.setup.gettingAround")) {
                Toggle(l("ui.setup.hasVehicle"), isOn: Binding(get: { draft!.transport.hasVehicle }, set: { on in
                    if on && draft!.transport.vehicles.isEmpty { draft!.transport.vehicles = [Vehicle(id: UUID().uuidString, seats: 1)] }
                    if !on { draft!.transport.vehicles = [] }
                }))
                ForEach(binding(\.transport.vehicles)) { $vehicle in
                    Stepper(l("family.seats", ["count": String(vehicle.seats)]), value: $vehicle.seats, in: 1...12)
                    TriStateRow(title: l("common.need.usesWheelchair"), value: $vehicle.wheelchairAccessible)
                }
                ForEach(binding(\.transport.alternatives)) { $alternative in
                    Picker(l("ui.setup.otherWay"), selection: $alternative.kind) {
                        ForEach(TransportAlternativeKind.allCases, id: \.self) { Text(l("common.transport.\($0.rawValue)")).tag($0) }
                    }
                    Picker(l("family.contacts"), selection: $alternative.contactID) {
                        Text(l("family.unknown")).tag(String?.none)
                        ForEach(draft!.contacts) { Text($0.alias).tag(Optional($0.id)) }
                    }
                    TriStateRow(title: l("ui.setup.agreed"), value: $alternative.agreed)
                    if draft!.people.contains(where: { $0.requiresStepFreeRoute }) {
                        TriStateRow(title: l("family.stepFreeTransport"), value: $alternative.wheelchairAccessible)
                    }
                }
                Button(l("ui.setup.addWay"), systemImage: "plus") {
                    draft!.transport.alternatives.append(TransportAlternative(id: UUID().uuidString, kind: .friendOrFamily))
                }
            }
            Section(l("card.section.goTo")) {
                ForEach(binding(\.transport.destinations)) { $destination in
                    TextField(l("ui.place.name"), text: $destination.label)
                    TriStateRow(title: l("ui.place.confirmed"), value: $destination.conditionsConfirmed)
                    TriStateRow(title: l("family.stepFreeTransport"), value: $destination.stepFreeAccess)
                }
                Button(l("ui.place.add"), systemImage: "plus") {
                    draft!.transport.destinations.append(RelocationDestination(id: UUID().uuidString, kind: .friendOrFamilyHome, label: ""))
                }
                Text(l("ui.place.footer")).font(.footnote)
            }
        }
    }
    private func fact(_ id: String) -> Binding<PreparationFact> {
        Binding(get: { draft!.preparedness?.items[id] ?? PreparationFact() }, set: { value in
            if draft!.preparedness == nil { draft!.preparedness = PreparednessRecord() }
            let current = draft!.preparedness!.items[id] ?? PreparationFact()
            draft!.preparedness!.items[id] = current.applyingEdits(value)
        })
    }
    private func preparationFields(_ id: String) -> some View {
        let l = model.localizer
        let record = fact(id)
        return Section {
            TriStateRow(title: l("family.haveItem"), value: record.available)
            TextField(l("family.locationOfItem"), text: record.location, axis: .vertical)
            TextField(l("family.notes"), text: record.notes, axis: .vertical)
            if BaselinePreparedness.definitions.contains(where: { $0.id == id }) || id == "pets" {
                Toggle(l("family.recordedCheck"), isOn: Binding(get: { record.wrappedValue.checkedAt != nil }, set: { record.wrappedValue.checkedAt = $0 ? Date() : nil }))
                if let date = record.wrappedValue.checkedAt {
                    Text(date, style: .date)
                    Button(l("family.recheckNow")) { record.wrappedValue.checkedAt = Date() }
                }
            }
            if id == "smokeAlarms" || id == "coAlarms" {
                TriStateRow(title: l("family.alarmCoverage"), value: Binding(get: { record.wrappedValue.coverageReviewed ?? .unknown }, set: { record.wrappedValue.coverageReviewed = $0 }))
                Text(l("family.alarmNote")).font(.footnote)
            }
            if id == "extinguisher" {
                TriStateRow(title: l("family.extinguisherAwareness"), value: Binding(get: { record.wrappedValue.familyAware ?? .unknown }, set: { record.wrappedValue.familyAware = $0 }))
                Text(l("family.extinguisherNote")).font(.footnote)
            }
        } header: { Text(l("prep.\(id).title")) }
    }
    private func save() {
        guard !saving, var value = draft else { return }
        if let fact = value.preparedness?.items["firstAid"] { value.supplies.firstAidKit = fact.available }
        if let fact = value.preparedness?.items["extinguisher"] { value.supplies.fireExtinguisher = fact.available }
        if let available = value.preparedness?.items["flashlight"]?.available.confirmedValue {
            if !available { value.supplies.flashlights = .confirmed(0) }
            else if (value.supplies.flashlights.confirmedValue ?? 0) < 1 { value.supplies.flashlights = .confirmed(1) }
        }
        value.contacts.removeAll { $0.alias.trimmingCharacters(in: .whitespaces).isEmpty && ($0.phone ?? "").isEmpty }
        saving = true
        Task {
            let saved = await model.updateHousehold(value)
            saving = false; saveFailed = !saved
            if saved { dismiss() }
        }
    }
}

/// Canonical storage remains US gallons; the form shows litres outside explicitly known US homes.
struct WaterStorageEvidenceRow: View {
    @Environment(AppModel.self) private var model
    @Binding var value: EvidenceValue<Double>
    let countryCode: String?
    @State private var text = ""
    private var usesGallons: Bool { countryCode?.uppercased() == "US" }
    private var conversion: Double { usesGallons ? 1 : 3.785411784 }
    var body: some View {
        TextField(model.localizer(usesGallons ? "ui.setup.water.gallons" : "family.waterLitres"), text: $text)
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("supplies.water")
            .onAppear { text = value.value.map { String($0 * conversion) } ?? "" }
            .onChange(of: text) { _, new in
                let parsed = Double(new.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")).map { $0 / conversion }
                if let parsed, let original = value.value, abs(parsed - original) < 1e-8 { return }
                guard parsed != value.value else { return }
                value = parsed.map { .confirmed($0, unit: "gal", verifiedAt: Date()) } ?? .unknown
            }
    }
}
