import SwiftUI
import DryRunCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        let l = model.localizer
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Image(systemName: "house.lodge.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, Theme.Space.l)
                        .accessibilityHidden(true)
                    Text(l("ui.onboarding.headline")).font(.largeTitle.weight(.bold))
                    Text(l("ui.onboarding.body")).font(.title3)
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        IconRow(systemImage: "bolt.slash.fill", tint: Theme.critical, title: l("ui.onboarding.point1"))
                        IconRow(systemImage: "list.bullet.clipboard.fill", tint: Theme.accent, title: l("ui.onboarding.point2"))
                        IconRow(systemImage: "lock.fill", tint: Theme.success, title: l("common.privacy.promise"))
                    }
                    .padding(.vertical, Theme.Space.s)

                    VStack(spacing: Theme.Space.s) {
                        Button {
                            Task { await model.startDemo() }
                        } label: {
                            Label(l("ui.onboarding.demo"), systemImage: "play.fill")
                        }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("onboarding.demo")
                        Text(l("ui.onboarding.demoNote")).font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Button { creating = true } label: {
                            Label(l("common.action.createHousehold"), systemImage: "person.2.badge.plus")
                        }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("onboarding.create")
                    }

                    Text(l("ui.onboarding.moreExamples")).font(.headline).padding(.top, Theme.Space.m)
                    ForEach(SampleHouseholds.all) { sample in
                        Button {
                            Task { await model.useSampleHousehold(sample) }
                        } label: {
                            HStack(spacing: Theme.Space.m) {
                                Text(Self.flag(sample.preferredLocale)).font(.title2).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sample.displayName).font(.body.weight(.semibold))
                                    Text(summary(sample)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(Theme.Space.m)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(l("ui.onboarding.sampleHint"))
                        .accessibilityIdentifier("onboarding.sample.\(sample.id)")
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Dry Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach([("en", "English"), ("es", "Español"), ("vi", "Tiếng Việt")], id: \.0) { code, name in
                            Button(name) { model.locale = code }
                        }
                    } label: {
                        Label(l("common.plan.language"), systemImage: "globe")
                    }
                    .accessibilityIdentifier("onboarding.language")
                }
            }
            .navigationDestination(isPresented: $creating) { HouseholdSetupView(mode: .create) }
        }
    }

    /// Language marker for each example household (its preferred language), not a nationality.
    static func flag(_ locale: String) -> String {
        switch locale { case "es": "ES"; case "vi": "VI"; default: "EN" }
    }

    private func summary(_ h: HouseholdProfile) -> String {
        let l = model.localizer
        var parts = [l("ui.onboarding.people", ["count": "\(h.people.count)"])]
        if let eq = h.equipment.first { parts.append(eq.label.lowercased()) }
        parts.append(h.housing.homeType.displayName.lowercased())
        if !h.transport.hasVehicle { parts.append(l("ui.onboarding.noCar")) }
        if h.housing.waterSource == .privateWell { parts.append(DisplayNames.name("privateWell").lowercased()) }
        return parts.joined(separator: " · ")
    }
}

/// Guided setup: one question per screen, in plain words, with "Not sure" always allowed. Unknown is preserved,
/// never defaulted to "no". Medical equipment, backup power, and contacts come early because they matter most in an
/// outage.
struct HouseholdSetupView: View {
    enum Mode { case create, edit }
    let mode: Mode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HouseholdProfile = HouseholdSetupView.blank()
    @State private var step = 0
    @State private var loaded = false

    enum Step: Int, CaseIterable { case area, people, medical, backup, home, contacts, travel }

    var body: some View {
        let l = model.localizer
        let current = Step(rawValue: step) ?? .area
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(l("ui.setup.stepOf", ["n": "\(step + 1)", "total": "\(Step.allCases.count)"]))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    ProgressView(value: Double(step + 1), total: Double(Step.allCases.count)).tint(Theme.accent)
                        .accessibilityHidden(true)
                    Text(l("ui.setup.\(current).question")).font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(l("ui.setup.\(current).why")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            switch current {
            case .area: areaStep
            case .people: peopleStep
            case .medical: equipmentStep
            case .backup: backupStep
            case .home: housingStep
            case .contacts: contactsStep
            case .travel: transportStep; petsStep; suppliesStep
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(mode == .create ? l("ui.setup.titleCreate") : l("ui.setup.titleEdit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .edit {
                ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(l("ui.save")) { save() } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AdaptiveStack(spacing: Theme.Space.s) {
                if step > 0 {
                    Button { withAnimation { step -= 1 } } label: { Label(l("ui.back"), systemImage: "chevron.left") }
                        .buttonStyle(.secondary)
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("setup.back")
                }
                if step < Step.allCases.count - 1 {
                    Button { withAnimation { step += 1 } } label: { Label(l("ui.next"), systemImage: "chevron.right") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("setup.next")
                } else {
                    Button { save() } label: { Label(l("ui.setup.finish"), systemImage: "checkmark") }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("setup.save")
                }
            }
            .padding(.horizontal).padding(.vertical, Theme.Space.s)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .background(.bar)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if mode == .edit, let h = model.household { draft = h } else { draft.preferredLocale = model.locale }
        }
    }

    // MARK: Steps

    private var areaStep: some View {
        let l = model.localizer
        return Section {
            Picker(l("common.plan.language"), selection: $draft.preferredLocale) {
                Text("English").tag("en"); Text("Español").tag("es"); Text("Tiếng Việt").tag("vi")
            }
            .onChange(of: draft.preferredLocale) { _, new in model.locale = new }
            Picker(l("ui.setup.county"), selection: $draft.regionID) {
                ForEach(Self.regions, id: \.id) { Text($0.name).tag($0.id) }
            }
        } footer: {
            Text(l("ui.setup.countyFooter"))
        }
    }

    private var peopleStep: some View {
        let l = model.localizer
        return Group {
            ForEach($draft.people) { $person in
                Section(person.alias.isEmpty ? l("ui.person") : person.alias) {
                    TextField(l("ui.setup.nickname"), text: $person.alias)
                    Picker(l("ui.setup.age"), selection: $person.ageBand) {
                        ForEach(AgeBand.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    ForEach(AssistanceNeed.allCases, id: \.self) { need in
                        Toggle(l("common.need.\(need.rawValue)"), isOn: Binding(
                            get: { person.needs.contains(need) },
                            set: { on in if on { person.needs.append(need) } else { person.needs.removeAll { $0 == need } } }))
                    }
                }
            }
            .onDelete { idx in if draft.people.count > idx.count { draft.people.remove(atOffsets: idx) } }
            Section {
                Button(l("ui.setup.addPerson"), systemImage: "person.badge.plus") {
                    draft.people.append(Person(id: "p-\(UUID().uuidString.prefix(8))", alias: "", ageBand: .adult))
                }
            }
        }
    }

    private var equipmentStep: some View {
        let l = model.localizer
        return Group {
            ForEach($draft.equipment) { $eq in
                Section {
                    Picker(l("ui.medical.purpose"), selection: $eq.purpose) {
                        ForEach(EquipmentPurpose.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField(l("ui.medical.label"), text: $eq.label)
                    Picker(l("ui.medical.usedBy"), selection: $eq.personID) {
                        Text(l("ui.notSure")).tag(String?.none)
                        ForEach(draft.people) { Text($0.alias.isEmpty ? l("ui.person") : $0.alias).tag(Optional($0.id)) }
                    }
                    Toggle(l("ui.medical.refrigeration"), isOn: $eq.needsRefrigeration)
                }
            }
            .onDelete { draft.equipment.remove(atOffsets: $0) }
            Section {
                Button(l("ui.card.addDevice"), systemImage: "plus") {
                    draft.equipment.append(PoweredEquipment(id: "eq-\(UUID().uuidString.prefix(8).lowercased())", purpose: .oxygenConcentrator,
                                                            label: EquipmentPurpose.oxygenConcentrator.displayName, personID: draft.people.first?.id))
                }
                .accessibilityIdentifier("setup.addDevice")
            } footer: {
                Text(draft.equipment.isEmpty ? l("ui.setup.medical.none") : l("ui.medical.noDiagnosis"))
            }
        }
    }

    private var backupStep: some View {
        let l = model.localizer
        return Group {
            ForEach($draft.backupPower) { $backup in
                Section {
                    TextField(l("ui.medical.backupName"), text: $backup.label)
                    Picker(l("ui.medical.backupKind"), selection: $backup.kind) {
                        ForEach(BackupPowerKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TriStateRow(title: l("ui.medical.tested"), value: $backup.setupConfirmed)
                    ForEach($draft.equipment) { $eq in
                        Toggle(l("ui.medical.worksWith", ["device": eq.label.isEmpty ? l("ui.medical.thisDevice") : eq.label]), isOn: Binding(
                            get: { eq.compatibleBackupIDs.contains(backup.id) },
                            set: { on in
                                if on { eq.compatibleBackupIDs.append(backup.id) } else { eq.compatibleBackupIDs.removeAll { $0 == backup.id } }
                            }))
                    }
                }
            }
            .onDelete { draft.backupPower.remove(atOffsets: $0) }
            Section {
                Button(l("ui.medical.addBackup"), systemImage: "plus") {
                    draft.backupPower.append(BackupPowerSource(id: "bk-\(UUID().uuidString.prefix(8).lowercased())", kind: .portableBatteryStation,
                                                               label: BackupPowerKind.portableBatteryStation.displayName))
                }
            } footer: {
                Text(l("ui.medical.backupFooter"))
            }
        }
    }

    private var housingStep: some View {
        let l = model.localizer
        return Group {
            Section {
                Picker(l("ui.setup.homeType"), selection: $draft.housing.homeType) { ForEach(HomeType.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Picker(l("ui.setup.tenancy"), selection: $draft.housing.tenancy) { ForEach(Tenancy.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Stepper(l("ui.setup.floors", ["count": "\(draft.housing.floorCount)"]), value: $draft.housing.floorCount, in: 1...4)
            }
            Section {
                Picker(l("ui.setup.heat"), selection: $draft.housing.heatingFuel) { ForEach(HeatingFuel.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                TriStateRow(title: l("ui.setup.heatNeedsPower"), value: $draft.housing.heatingNeedsElectricity)
                Picker(l("ui.setup.cooling"), selection: $draft.housing.cooling) { ForEach(CoolingKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
            } footer: {
                Text(l("ui.setup.heatFooter"))
            }
            Section {
                Picker(l("ui.setup.water"), selection: $draft.housing.waterSource) { ForEach(WaterSourceKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                if draft.housing.waterSource == .privateWell {
                    TriStateRow(title: l("ui.setup.wellPump"), value: $draft.housing.wellPumpElectric)
                }
                Picker(l("ui.setup.sanitation"), selection: $draft.housing.sanitation) { ForEach(SanitationKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
            }
        }
    }

    private var contactsStep: some View {
        let l = model.localizer
        return Group {
            ForEach($draft.contacts) { $c in
                Section {
                    Picker(l("ui.contact.role"), selection: $c.role) {
                        ForEach(ContactRole.allCases, id: \.self) { Text(l("ui.contact.role.\($0.rawValue)")).tag($0) }
                    }
                    TextField(l("ui.contact.name"), text: $c.alias)
                    TextField(l("ui.contact.phone"), text: Binding(get: { c.phone ?? "" }, set: { c.phone = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.phonePad)
                }
            }
            .onDelete { draft.contacts.remove(atOffsets: $0) }
            Section {
                ForEach([ContactRole.outOfAreaContact, .careProvider, .neighborHelper], id: \.self) { role in
                    Button(l("ui.contact.role.\(role.rawValue)"), systemImage: "plus") {
                        draft.contacts.append(HouseholdContact(id: "ct-\(UUID().uuidString.prefix(8).lowercased())", role: role, alias: ""))
                    }
                }
            } footer: {
                Text(l("ui.contact.footer"))
            }
        }
    }

    private var transportStep: some View {
        let l = model.localizer
        return Section {
            Toggle(l("ui.setup.hasVehicle"), isOn: Binding(
                get: { draft.transport.hasVehicle },
                set: { on in draft.transport.vehicles = on ? [Vehicle(id: "veh-1", seats: 5)] : [] }))
            ForEach($draft.transport.alternatives) { $alt in
                Picker(l("ui.setup.otherWay"), selection: $alt.kind) {
                    ForEach(TransportAlternativeKind.allCases, id: \.self) { Text(l("common.transport.\($0.rawValue)")).tag($0) }
                }
                TriStateRow(title: l("ui.setup.agreed"), value: $alt.agreed)
            }
            Button(l("ui.setup.addWay"), systemImage: "plus") {
                draft.transport.alternatives.append(TransportAlternative(id: "ta-\(UUID().uuidString.prefix(8))", kind: .friendOrFamily))
            }
        } header: {
            Text(l("ui.setup.gettingAround"))
        } footer: {
            Text(l("ui.setup.noCarFooter"))
        }
    }

    private var petsStep: some View {
        let l = model.localizer
        return Section(l("ui.setup.pets")) {
            ForEach($draft.pets) { $pet in
                Picker(l("ui.medical.backupKind"), selection: $pet.kind) { ForEach(PetKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Stepper(l("ui.setup.petCount", ["count": "\(pet.count)"]), value: $pet.count, in: 1...20)
                TriStateRow(title: l("ui.setup.carrier"), value: $pet.carrierAvailable)
            }
            Button(l("ui.setup.addPet"), systemImage: "plus") { draft.pets.append(Pet(id: "pet-\(UUID().uuidString.prefix(8))", kind: .dog)) }
        }
    }

    private var suppliesStep: some View {
        let l = model.localizer
        return Section(l("ui.setup.supplies")) {
            NumberEvidenceRow(title: l("ui.setup.water.gallons"), value: $draft.supplies.storedWaterGallons, unit: "gal")
            NumberEvidenceRow(title: l("ui.setup.food.days"), value: $draft.supplies.shelfStableFoodDays, unit: "d")
            Toggle(l("ui.setup.limitedSpace"), isOn: $draft.supplies.limitedStorageSpace)
            Toggle(l("ui.setup.limitedBudget"), isOn: $draft.supplies.limitedBudget)
        }
    }

    private func save() {
        draft.contacts.removeAll { $0.alias.trimmingCharacters(in: .whitespaces).isEmpty && ($0.phone ?? "").isEmpty }
        for i in draft.equipment.indices where draft.equipment[i].label.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.equipment[i].label = draft.equipment[i].purpose.displayName
        }
        Task {
            let saved: Bool
            if mode == .create {
                saved = await model.useSampleHouseholdIfNoHome(draft)
            } else {
                let d = draft
                saved = await model.updateHousehold { $0 = d }
                // The language chosen here is the app's language; without this it only changed after a relaunch.
                if saved { model.locale = d.preferredLocale }
            }
            if saved { dismiss() }
        }
    }

    static func blank() -> HouseholdProfile {
        HouseholdProfile(
            id: "hh-\(UUID().uuidString.prefix(8))", displayName: "My household", regionID: "48143",
            people: [Person(id: "p-1", alias: "Me", ageBand: .adult)],
            housing: Housing(homeType: .singleFamily, tenancy: .owner, heatingFuel: .unknown, cooling: .unknown, waterSource: .unknown),
            transport: Transport(), supplies: Supplies())
    }

    /// TX-25 counties (all or parts of 13). Partial-county membership is not asserted here.
    static let regions: [(id: String, name: String)] = [
        ("48059", "Callahan"), ("48093", "Comanche"), ("48133", "Eastland"), ("48143", "Erath"), ("48221", "Hood"),
        ("48237", "Jack"), ("48251", "Johnson"), ("48363", "Palo Pinto"), ("48367", "Parker"), ("48425", "Somervell"),
        ("48429", "Stephens"), ("48439", "Tarrant"), ("48503", "Young"),
    ]
}

/// Yes / No / Not sure. "Not sure" keeps the value unknown.
struct TriStateRow: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var value: EvidenceValue<Bool>

    var body: some View {
        Picker(title, selection: Binding<Int>(
            get: { value.value == nil ? 2 : (value.value! ? 0 : 1) },
            set: { value = $0 == 2 ? .unknown : .confirmed($0 == 0, verifiedAt: Date()) })) {
            Text(model.localizer("ui.yes")).tag(0); Text(model.localizer("ui.no")).tag(1); Text(model.localizer("ui.notSure")).tag(2)
        }
    }
}

struct NumberEvidenceRow: View {
    let title: String
    @Binding var value: EvidenceValue<Double>
    let unit: String
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .onAppear { text = value.value.map { String($0) } ?? "" }
            .onChange(of: text) { _, new in
                // Accept a decimal comma (Spanish and Vietnamese keyboards), and only store a real edit: filling the
                // field on appear must not re-stamp an existing value as confirmed just now.
                let parsed = Double(new.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
                guard parsed != value.value else { return }
                if let parsed {
                    value = EvidenceValue<Double>.confirmed(parsed, unit: unit, verifiedAt: Date())
                } else {
                    value = EvidenceValue<Double>.unknown
                }
            }
            .accessibilityLabel("\(title). Leave empty if not sure.")
    }
}
