import SwiftUI
import DryRunCore

/// Both household and continuity forms edit the same fields and support semantics.
struct EquipmentEditorFields: View {
    @Environment(AppModel.self) private var model
    @Binding var equipment: PoweredEquipment
    let people: [Person]
    var body: some View {
        let l = model.localizer
        Picker(l("ui.medical.purpose"), selection: Binding(get: { equipment.purpose }, set: { equipment.changePurpose(to: $0) })) {
            ForEach(EquipmentPurpose.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: l)).tag($0) }
        }
        TextField(l("family.optionalName"), text: Binding(get: { equipment.label }, set: { equipment.label = $0; equipment.labelIsCustom = !$0.isEmpty })).accessibilityIdentifier("medical.label")
        Picker(l("ui.medical.usedBy"), selection: $equipment.personID) {
            Text(l("ui.notSure")).tag(String?.none)
            ForEach(people) { Text($0.alias.isEmpty ? l($0.isSelf == true ? "family.you" : "ui.person") : $0.alias).tag(Optional($0.id)) }
        }
        if equipment.purpose == .refrigeratedMedication || equipment.needsRefrigeration || equipment.refrigeratedStorage != nil {
            TriStateRow(title: l(equipment.purpose == .refrigeratedMedication ? "family.refrigeration" : "family.itemRefrigeration"), value: Binding(get: { equipment.refrigeratedStorage ?? .unknown }, set: { equipment.refrigeratedStorage = $0 }))
            if equipment.purpose == .refrigeratedMedication {
                TriStateRow(title: l("family.power"), value: Binding(get: { equipment.electricalRequirement ?? .confirmed(false) }, set: { equipment.electricalRequirement = $0 }))
            }
            if equipment.requiresColdStorage {
                TextField(l(equipment.purpose == .refrigeratedMedication ? "family.storageInstructions" : "family.itemStorageInstructions"), text: Binding(get: { equipment.storageInstructions ?? "" }, set: { equipment.storageInstructions = $0 }), axis: .vertical)
                TriStateRow(title: l("family.storagePlan"), value: Binding(get: { equipment.storagePlanConfirmed ?? .unknown }, set: { equipment.storagePlanConfirmed = $0 }))
            }
            Text(l("family.providerPrompt")).font(.footnote)
        }
    }
}

struct BackupEditorFields: View {
    @Environment(AppModel.self) private var model
    @Binding var backup: BackupPowerSource
    let onKindChanged: (String) -> Void
    var body: some View {
        let l = model.localizer
        Picker(l("ui.medical.backupKind"), selection: Binding(get: { backup.kind }, set: { value in
            guard backup.kind != value else { return }
            let id = backup.id
            backup.changeKind(to: value)
            onKindChanged(id)
        })) {
            ForEach(BackupPowerKind.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: l)).tag($0) }
        }
        TextField(l("family.optionalName"), text: Binding(get: { backup.label }, set: { backup.label = $0; backup.labelIsCustom = !$0.isEmpty }))
        TriStateRow(title: l("ui.medical.tested"), value: $backup.setupConfirmed)
        if backup.kind == .portableGenerator || backup.kind == .standbyGenerator {
            TriStateRow(title: l("action.act.generator.outdoor-placement.title"), value: $backup.safeOutdoorPlacementConfirmed)
        }
    }
}
