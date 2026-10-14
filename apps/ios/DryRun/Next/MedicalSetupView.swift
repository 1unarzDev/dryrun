import SwiftUI
import DryRunCore

/// Everything an outage card needs for one device, in one form: who uses it, which backup works with it and whether
/// it was tested, the documented runtime, the supplier or care team, an out-of-area contact, and a confirmed place
/// to go. Every answer can stay "Not sure"; unknown stays unknown. Saving bumps the household revision.
struct MedicalSetupView: View {
    static let newDeviceID = "__new__"
    let equipmentID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HouseholdProfile?
    @State private var deviceID = ""

    var body: some View {
        let l = model.localizer
        Form {
            if let index = deviceIndex {
                deviceSection(index)
                backupSection(index)
                runtimeSection(index)
                contactsSection
                destinationSection
            }
        }
        .navigationTitle(equipmentID == Self.newDeviceID ? l("ui.card.addDevice") : l("ui.medical.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(l("ui.save")) { save() }.accessibilityIdentifier("medical.save")
            }
        }
        .onAppear(perform: load)
    }

    private var deviceIndex: Int? { draft?.equipment.firstIndex { $0.id == deviceID } }

    private func load() {
        guard draft == nil, var h = model.household else { return }
        if equipmentID == Self.newDeviceID || !h.equipment.contains(where: { $0.id == equipmentID }) {
            let id = "eq-\(UUID().uuidString.prefix(8).lowercased())"
            h.equipment.append(PoweredEquipment(id: id, purpose: .oxygenConcentrator, label: "", personID: h.people.first?.id))
            deviceID = id
        } else {
            deviceID = equipmentID
        }
        draft = h
    }

    private func binding<T>(_ path: WritableKeyPath<HouseholdProfile, T>) -> Binding<T> {
        Binding(get: { draft![keyPath: path] }, set: { draft![keyPath: path] = $0 })
    }

    // MARK: Sections

    private func deviceSection(_ i: Int) -> some View {
        let l = model.localizer
        let eq = binding(\.equipment[i])
        return Section {
            Picker(l("ui.medical.purpose"), selection: eq.purpose) {
                ForEach(EquipmentPurpose.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .onChange(of: eq.wrappedValue.purpose) { old, new in
                // Keep a typed label; fill an empty or default one from the purpose.
                if eq.wrappedValue.label.isEmpty || eq.wrappedValue.label == old.displayName { eq.wrappedValue.label = new.displayName }
            }
            TextField(l("ui.medical.label"), text: eq.label)
                .accessibilityIdentifier("medical.label")
            Picker(l("ui.medical.usedBy"), selection: eq.personID) {
                Text(l("ui.notSure")).tag(String?.none)
                ForEach(draft?.people ?? []) { Text($0.alias.isEmpty ? l("ui.person") : $0.alias).tag(Optional($0.id)) }
            }
            Toggle(l("ui.medical.refrigeration"), isOn: eq.needsRefrigeration)
        } header: {
            Text(l("ui.medical.device"))
        } footer: {
            Text(l("ui.medical.noDiagnosis"))
        }
    }

    private func backupSection(_ i: Int) -> some View {
        let l = model.localizer
        let eq = binding(\.equipment[i])
        return Section {
            ForEach(binding(\.backupPower)) { $backup in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    TextField(l("ui.medical.backupName"), text: $backup.label).font(.body.weight(.semibold))
                    Picker(l("ui.medical.backupKind"), selection: $backup.kind) {
                        ForEach(BackupPowerKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Toggle(l("ui.medical.worksWith", ["device": eq.wrappedValue.label.isEmpty ? l("ui.medical.thisDevice") : eq.wrappedValue.label]),
                           isOn: Binding(
                            get: { eq.wrappedValue.compatibleBackupIDs.contains(backup.id) },
                            set: { on in
                                if on { eq.wrappedValue.compatibleBackupIDs.append(backup.id) }
                                else { eq.wrappedValue.compatibleBackupIDs.removeAll { $0 == backup.id } }
                            }))
                    .accessibilityIdentifier("medical.worksWith")
                    TriStateRow(title: l("ui.medical.tested"), value: $backup.setupConfirmed)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            Button(l("ui.medical.addBackup"), systemImage: "plus") {
                let id = "bk-\(UUID().uuidString.prefix(8).lowercased())"
                draft?.backupPower.append(BackupPowerSource(id: id, kind: .portableBatteryStation,
                                                            label: BackupPowerKind.portableBatteryStation.displayName))
                draft?.equipment[i].compatibleBackupIDs.append(id)
            }
            .accessibilityIdentifier("medical.addBackup")
        } header: {
            Text(l("card.section.backup"))
        } footer: {
            Text(l("ui.medical.backupFooter"))
        }
    }

    private func runtimeSection(_ i: Int) -> some View {
        let l = model.localizer
        return Section {
            NumberEvidenceRow(title: l("ui.medical.runtimeHours"), value: binding(\.equipment[i].documentedBackupRuntimeHours), unit: "h")
                .accessibilityIdentifier("medical.runtime")
        } header: {
            Text(l("ui.medical.runtime"))
        } footer: {
            Text(l("ui.medical.runtimeFooter"))
        }
    }

    private var contactsSection: some View {
        let l = model.localizer
        let roles: [ContactRole] = [.careProvider, .utilityMedicalRegistry, .outOfAreaContact, .neighborHelper]
        return Section {
            ForEach(binding(\.contacts)) { $c in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Picker(l("ui.contact.role"), selection: $c.role) {
                        ForEach(ContactRole.allCases, id: \.self) { Text(l("ui.contact.role.\($0.rawValue)")).tag($0) }
                    }
                    TextField(l("ui.contact.name"), text: $c.alias)
                    TextField(l("ui.contact.phone"), text: Binding(get: { c.phone ?? "" },
                                                                   set: { c.phone = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            .onDelete { draft?.contacts.remove(atOffsets: $0) }
            Menu {
                ForEach(roles, id: \.self) { role in
                    Button(l("ui.contact.role.\(role.rawValue)")) {
                        draft?.contacts.append(HouseholdContact(id: "ct-\(UUID().uuidString.prefix(8).lowercased())", role: role, alias: ""))
                    }
                }
            } label: {
                Label(l("ui.contact.add"), systemImage: "person.crop.circle.badge.plus")
            }
            .accessibilityIdentifier("medical.addContact")
        } header: {
            Text(l("card.section.contacts"))
        } footer: {
            Text(l("ui.contact.footer"))
        }
    }

    private var destinationSection: some View {
        let l = model.localizer
        return Section {
            ForEach(binding(\.transport.destinations)) { $d in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    TextField(l("ui.place.name"), text: $d.label)
                    Picker(l("ui.place.kind"), selection: $d.kind) {
                        ForEach(DestinationKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TriStateRow(title: l("ui.place.confirmed"), value: $d.conditionsConfirmed)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            .onDelete { draft?.transport.destinations.remove(atOffsets: $0) }
            Button(l("ui.place.add"), systemImage: "plus") {
                draft?.transport.destinations.append(RelocationDestination(id: "dest-\(UUID().uuidString.prefix(8).lowercased())",
                                                                           kind: .friendOrFamilyHome, label: ""))
            }
            .accessibilityIdentifier("medical.addPlace")
        } header: {
            Text(l("card.section.goTo"))
        } footer: {
            Text(l("ui.place.footer"))
        }
    }

    private func save() {
        guard var d = draft else { return dismiss() }
        // Drop empty rows instead of saving blank names.
        d.contacts.removeAll { $0.alias.trimmingCharacters(in: .whitespaces).isEmpty && ($0.phone ?? "").isEmpty }
        d.transport.destinations.removeAll { $0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        if let i = d.equipment.firstIndex(where: { $0.id == deviceID }), d.equipment[i].label.trimmingCharacters(in: .whitespaces).isEmpty {
            d.equipment[i].label = d.equipment[i].purpose.displayName
        }
        let final = d
        Task {
            await model.updateHousehold { $0 = final }
            dismiss()
        }
    }
}
