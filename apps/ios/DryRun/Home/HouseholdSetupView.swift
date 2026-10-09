import SwiftUI
import DryRunCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Rehearse the first minutes and the next 72 hours of an emergency in your own home.")
                        .font(.title3)
                    Text(model.localizer("common.privacy.promise"))
                        .font(.callout).foregroundStyle(.secondary)

                    Text("Try a fictional household").font(.headline).padding(.top)
                    ForEach(SampleHouseholds.all) { sample in
                        Button {
                            Task { await model.useSampleHousehold(sample) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sample.displayName).font(.body.weight(.semibold))
                                Text(summary(sample)).font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Loads a made-up household and sample home")
                        .accessibilityIdentifier("onboarding.sample.\(sample.id)")
                    }

                    Button {
                        creating = true
                    } label: {
                        Label(model.localizer("common.action.createHousehold"), systemImage: "person.2.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Dry Run")
            .navigationDestination(isPresented: $creating) { HouseholdSetupView(mode: .create) }
        }
    }

    private func summary(_ h: HouseholdProfile) -> String {
        var parts = ["\(h.people.count) people"]
        if !h.pets.isEmpty { parts.append("pets") }
        parts.append(h.housing.homeType.rawValue)
        if !h.transport.hasVehicle { parts.append("no car") }
        if !h.equipment.isEmpty { parts.append("essential equipment") }
        if h.housing.waterSource == .privateWell { parts.append("private well") }
        return parts.joined(separator: " · ")
    }
}

/// Progressive questions. Every answer can stay "Not sure"; unknown is preserved, never defaulted to "no".
struct HouseholdSetupView: View {
    enum Mode { case create, edit }
    let mode: Mode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HouseholdProfile = HouseholdSetupView.blank()
    @State private var step = 0
    private let steps = ["Area and language", "People", "Pets", "Home and utilities", "Essential equipment", "Getting around", "Supplies"]

    var body: some View {
        Form {
            Section {
                ProgressView(value: Double(step + 1), total: Double(steps.count)) {
                    Text("Step \(step + 1) of \(steps.count): \(steps[step])")
                }
            }
            switch step {
            case 0: areaStep
            case 1: peopleStep
            case 2: petsStep
            case 3: housingStep
            case 4: equipmentStep
            case 5: transportStep
            default: suppliesStep
            }
        }
        .navigationTitle(mode == .create ? "Your household" : "Edit household")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("Back") { step -= 1 }.disabled(step == 0)
                    Spacer()
                    if step < steps.count - 1 {
                        Button("Next") { step += 1 }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Save") { save() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .onAppear { if mode == .edit, let h = model.household { draft = h } }
    }

    // MARK: Steps

    private var areaStep: some View {
        Section {
            Picker("County", selection: $draft.regionID) {
                ForEach(Self.regions, id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker("Plan language", selection: $draft.preferredLocale) {
                Text("English").tag("en"); Text("Español").tag("es"); Text("Tiếng Việt").tag("vi")
            }
        } footer: {
            Text("Only your county is used to choose public resources. Your address is optional and stays on this phone.")
        }
    }

    private var peopleStep: some View {
        Group {
            ForEach($draft.people) { $person in
                Section(person.alias.isEmpty ? "Person" : person.alias) {
                    TextField("Nickname (no legal name needed)", text: $person.alias)
                    Picker("Age group", selection: $person.ageBand) {
                        ForEach(AgeBand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    ForEach(AssistanceNeed.allCases, id: \.self) { need in
                        Toggle(model.localizer("common.need.\(need.rawValue)"), isOn: Binding(
                            get: { person.needs.contains(need) },
                            set: { on in if on { person.needs.append(need) } else { person.needs.removeAll { $0 == need } } }))
                    }
                }
            }
            Button("Add person", systemImage: "plus") {
                draft.people.append(Person(id: "p-\(UUID().uuidString.prefix(8))", alias: "", ageBand: .adult))
            }
        }
    }

    private var petsStep: some View {
        Section("Pets") {
            ForEach($draft.pets) { $pet in
                Picker("Kind", selection: $pet.kind) { ForEach(PetKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Stepper("Count: \(pet.count)", value: $pet.count, in: 1...20)
                TriStateRow(title: "Carrier or leash ready", value: $pet.carrierAvailable)
            }
            Button("Add pet", systemImage: "plus") { draft.pets.append(Pet(id: "pet-\(UUID().uuidString.prefix(8))", kind: .dog)) }
        }
    }

    private var housingStep: some View {
        Group {
            Section("Home") {
                Picker("Home type", selection: $draft.housing.homeType) { ForEach(HomeType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("You", selection: $draft.housing.tenancy) { ForEach(Tenancy.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Stepper("Floors: \(draft.housing.floorCount)", value: $draft.housing.floorCount, in: 1...4)
            }
            Section {
                Picker("Main heat", selection: $draft.housing.heatingFuel) { ForEach(HeatingFuel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TriStateRow(title: "Heat needs electricity (controls, blower, or electric heat)", value: $draft.housing.heatingNeedsElectricity)
                Picker("Cooling", selection: $draft.housing.cooling) { ForEach(CoolingKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } footer: {
                Text("Many gas furnaces still need electricity for the blower or controls. If you are not sure, leave it as Not sure.")
            }
            Section("Water and sanitation") {
                Picker("Water", selection: $draft.housing.waterSource) { ForEach(WaterSourceKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                if draft.housing.waterSource == .privateWell {
                    TriStateRow(title: "Well pump is electric", value: $draft.housing.wellPumpElectric)
                }
                Picker("Sanitation", selection: $draft.housing.sanitation) { ForEach(SanitationKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
        }
    }

    private var equipmentStep: some View {
        Section {
            ForEach($draft.equipment) { $eq in
                Picker("Purpose", selection: $eq.purpose) { ForEach(EquipmentPurpose.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Label", text: $eq.label)
                Toggle("Needs refrigeration (not power directly)", isOn: $eq.needsRefrigeration)
            }
            Button("Add essential equipment", systemImage: "plus") {
                draft.equipment.append(PoweredEquipment(id: "eq-\(UUID().uuidString.prefix(8))", purpose: .other, label: ""))
            }
        } footer: {
            Text("Choose what the equipment is for. No diagnosis is needed. Backup runtimes come from the manufacturer or care plan, never from Dry Run.")
        }
    }

    private var transportStep: some View {
        Section {
            Toggle("Household has a vehicle", isOn: Binding(
                get: { draft.transport.hasVehicle },
                set: { on in draft.transport.vehicles = on ? [Vehicle(id: "veh-1", seats: 5)] : [] }))
            ForEach($draft.transport.alternatives) { $alt in
                Picker("Alternative", selection: $alt.kind) {
                    ForEach(TransportAlternativeKind.allCases, id: \.self) { Text(model.localizer("common.transport.\($0.rawValue)")).tag($0) }
                }
                TriStateRow(title: "Agreed in advance", value: $alt.agreed)
            }
            Button("Add another way to travel", systemImage: "plus") {
                draft.transport.alternatives.append(TransportAlternative(id: "ta-\(UUID().uuidString.prefix(8))", kind: .friendOrFamily))
            }
        } footer: {
            Text("No car is a fully supported plan. Arranging a ride ahead of time matters more than owning one.")
        }
    }

    private var suppliesStep: some View {
        Section("Supplies") {
            NumberEvidenceRow(title: "Stored drinking water (gallons)", value: $draft.supplies.storedWaterGallons, unit: "gal")
            NumberEvidenceRow(title: "Shelf-stable food (days)", value: $draft.supplies.shelfStableFoodDays, unit: "d")
            Toggle("Limited storage space", isOn: $draft.supplies.limitedStorageSpace)
            Toggle("Limited budget", isOn: $draft.supplies.limitedBudget)
        }
    }

    private func save() {
        Task {
            if mode == .create {
                await model.useSampleHouseholdIfNoHome(draft)
            } else {
                let d = draft
                await model.updateHousehold { $0 = d }
                // The language chosen here is the app's language; without this it only changed after a relaunch.
                model.locale = d.preferredLocale
            }
            dismiss()
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
    let title: String
    @Binding var value: EvidenceValue<Bool>

    var body: some View {
        Picker(title, selection: Binding<Int>(
            get: { value.value == nil ? 2 : (value.value! ? 0 : 1) },
            set: { value = $0 == 2 ? .unknown : .confirmed($0 == 0, verifiedAt: Date()) })) {
            Text("Yes").tag(0); Text("No").tag(1); Text("Not sure").tag(2)
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

extension AppModel {
    /// New households start with the fictional sample home until the user builds or scans their own,
    /// which is clearly labeled in the Home tab.
    func useSampleHouseholdIfNoHome(_ household: HouseholdProfile) async {
        self.household = household
        if home == nil { home = SampleHomes.ranch }
        locale = household.preferredLocale
        phase = .ready
        await persist()
    }
}
