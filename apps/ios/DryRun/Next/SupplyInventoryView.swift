import SwiftUI
import DryRunCore

/// "What do you already have?": typed supply items reviewed once as a batch, then held in the confirmed inventory.
/// Quantities stay unknown unless entered; "ready to use" and "can reach it" are separate facts; gaps come from Core.
/// An item recorded here is the household's own report, not proof that it works or is compatible with a device.
struct SupplyInventoryView: View {
    @Environment(AppModel.self) private var model
    @State private var staged: [InventoryItem] = []
    @State private var kind: Kind = .water
    @State private var quantityText = ""
    @State private var ready: Bool? = nil
    @State private var reachable: Bool? = nil
    @State private var roomID = ""
    @State private var saving = false
    @State private var saveFailed = false
    /// The decimal pad has no Return key; a keyboard Done button and scrolling both dismiss it.
    @FocusState private var editingQuantity: Bool

    /// Reviewed kinds only. Category, unit and preparation identity are fixed per kind so nothing is guessed.
    enum Kind: String, CaseIterable, Identifiable {
        case water, foodDays, flashlight, firstAidKit, power, other
        var id: String { rawValue }
        var category: String {
            switch self {
            case .water: "water"
            case .foodDays: "food"
            case .flashlight: "light"
            case .firstAidKit: "firstAid"
            case .power: "power"
            case .other: "other"
            }
        }
        var unit: InventoryUnit {
            switch self {
            case .water: .usGallon
            case .foodDays: .day
            case .flashlight, .firstAidKit, .other: .count
            case .power: .wattHour
            }
        }
        var preparationKind: InventoryPreparationKind? {
            switch self {
            case .flashlight: .flashlight
            case .firstAidKit: .firstAidKit
            default: nil
            }
        }
        var symbol: String {
            switch self {
            case .water: "drop"
            case .foodDays: "fork.knife"
            case .flashlight: "flashlight.on.fill"
            case .firstAidKit: "cross.case"
            case .power: "battery.100.bolt"
            case .other: "shippingbox"
            }
        }
    }

    var body: some View {
        let l = model.localizer
        List {
            Section {
                Text(l("inventory.intro")).font(.callout)
            }
            recorded
            legacyReconciliation
            Section(l("inventory.add")) {
                Picker(l("inventory.kind"), selection: $kind) {
                    ForEach(Kind.allCases) { Label(l("inventory.kind.\($0.rawValue)"), systemImage: $0.symbol).tag($0) }
                }
                .accessibilityIdentifier("inventory.kind")
                HStack {
                    TextField(l("inventory.quantity"), text: $quantityText)
                        .keyboardType(.decimalPad)
                        .focused($editingQuantity)
                        .accessibilityIdentifier("inventory.quantity")
                    Text(l("inventory.unit.\(kind.unit.rawValue)")).foregroundStyle(.secondary)
                }
                Text(l("inventory.quantityHint")).font(.caption).foregroundStyle(.secondary)
                triState(l("inventory.ready"), $ready, id: "inventory.ready")
                triState(l("inventory.reachable"), $reachable, id: "inventory.reachable")
                if let home = model.home {
                    Picker(l("inventory.room"), selection: $roomID) {
                        Text(l("family.unknown")).tag("")
                        ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                    }
                }
                Button(l("inventory.stage")) { stage() }
                    .disabled(parsedQuantity == .invalid)
                    .accessibilityIdentifier("inventory.stage")
                if parsedQuantity == .invalid {
                    Text(l("inventory.invalidQuantity")).font(.footnote).foregroundStyle(Theme.caution)
                }
            }
            if !staged.isEmpty {
                Section(l("inventory.review")) {
                    ForEach(staged, id: \.id) { row($0) }
                        .onDelete { staged.remove(atOffsets: $0) }
                    Button {
                        Task {
                            saving = true
                            saveFailed = !(await model.confirmInventory(staged))
                            if !saveFailed { staged = [] }
                            saving = false
                        }
                    } label: {
                        Label(l("inventory.confirm", ["count": "\(staged.count)"]), systemImage: "checkmark.circle")
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("inventory.confirm")
                    if saveFailed { Text(l("inventory.saveFailed")).font(.footnote).foregroundStyle(Theme.caution) }
                }
            }
            gaps
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(l("common.done")) { editingQuantity = false }.accessibilityIdentifier("inventory.keyboardDone")
            }
        }
        .navigationTitle(l("inventory.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    @ViewBuilder private var recorded: some View {
        let items = model.aiState.inventory.items
        if !items.isEmpty {
            Section(model.localizer("inventory.recorded")) {
                ForEach(items, id: \.id) { row($0) }
            }
            .accessibilityIdentifier("inventory.recorded")
        }
    }

    /// A gallon total recorded before the item list existed is brought in explicitly, once, never counted twice.
    @ViewBuilder private var legacyReconciliation: some View {
        let l = model.localizer
        if let gallons = model.household?.supplies.storedWaterGallons.confirmedValue,
           !model.aiState.inventory.items.contains(where: { $0.category == "water" }),
           !staged.contains(where: { $0.category == "water" }) {
            Section {
                Button(l("inventory.useRecordedWater", ["amount": ServiceNames.quantity(gallons, unit: "gal", localizer: l)])) {
                    if let legacy = try? InventoryLedger.migrating(model.household!.supplies, at: Date()).items.first { staged.append(legacy) }
                }
                .accessibilityIdentifier("inventory.useRecordedWater")
            }
        }
    }

    @ViewBuilder private var gaps: some View {
        let l = model.localizer
        let gaps = model.inventoryGaps
        if !gaps.isEmpty {
            Section {
                ForEach(gaps, id: \.category) { gap in
                    let name = l("inventory.gap.\(gap.category)")
                    let detail: String = if gap.unknown {
                        l("inventory.gapUnknown")
                    } else if let deficit = gap.deficit, deficit > 0 {
                        l("inventory.gapShort", ["amount": amount(deficit, unit: gap.unit)])
                    } else {
                        l("inventory.gapCovered", ["amount": amount(gap.required, unit: gap.unit)])
                    }
                    IconRow(systemImage: gap.unknown ? "questionmark.circle" : (gap.deficit ?? 0) > 0 ? "exclamationmark.circle" : "checkmark.circle",
                            tint: gap.unknown ? Theme.caution : (gap.deficit ?? 0) > 0 ? Theme.critical : Theme.accent,
                            title: name, subtitle: detail)
                }
            } header: {
                Text(l("inventory.gaps"))
            } footer: {
                Text(l("inventory.gapsFooter"))
            }
            .accessibilityIdentifier("inventory.gaps")
        }
    }

    private func row(_ item: InventoryItem) -> some View {
        let l = model.localizer
        let kind = Kind.allCases.first { $0.category == item.category && $0.preparationKind == item.preparationKind } ?? .other
        let quantity = item.quantity.confirmedValue.map { amount($0, unit: item.unit.rawValue) } ?? l("family.unknown")
        var facts: [String] = []
        if let usable = item.usableQuantity.confirmedValue { facts.append(l("inventory.readyAmount", ["amount": amount(usable, unit: item.unit.rawValue)])) }
        if let reach = item.accessible.confirmedValue { facts.append(l(reach ? "inventory.canReach" : "inventory.cannotReach")) }
        if let room = item.locationID, let home = model.home, home.space(room) != nil { facts.append(HomeScenePresentation.roomLabel(room, in: home)) }
        return IconRow(systemImage: kind.symbol, title: "\(l("inventory.kind.\(kind.rawValue)")) · \(quantity)",
                       subtitle: facts.isEmpty ? nil : facts.joined(separator: " · "))
    }

    // MARK: Entry

    /// One tap per fact: usable and reachable stay separate, and "not sure" stays unknown rather than no.
    private func triState(_ title: String, _ value: Binding<Bool?>, id: String) -> some View {
        let l = model.localizer
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
            Picker(title, selection: value) {
                Text(l("inventory.notSure")).tag(Bool?.none)
                Text(l("ui.yes")).tag(Bool?.some(true))
                Text(l("ui.no")).tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(id)
        }
    }

    private enum Parsed: Equatable { case unknown, value(Double), invalid }

    private var parsedQuantity: Parsed {
        let text = quantityText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return .unknown }
        guard let value = Double(text), value.isFinite, value >= 0, value < 100_000 else { return .invalid }
        if kind.unit == .count, value.rounded(.towardZero) != value { return .invalid }
        return .value(value)
    }

    private func stage() {
        let quantity: EvidenceValue<Double>
        switch parsedQuantity {
        case .invalid: return
        case .unknown: quantity = .unknown
        case .value(let v): quantity = .confirmed(v)
        }
        let id = "item-\(UUID().uuidString)"
        // "Ready to use" confirms the whole entered amount as usable; "no" records zero usable, never a guess between.
        let usable: EvidenceValue<Double> = switch (ready, quantity.confirmedValue) {
        case (true?, let q?): .confirmed(q)
        case (false?, _): .confirmed(0)
        default: .unknown
        }
        staged.append(InventoryItem(id: id, physicalID: id, category: kind.category, quantity: quantity, unit: kind.unit,
                                    usableQuantity: usable, accessible: reachable.map { .confirmed($0) } ?? .unknown,
                                    locationID: roomID.isEmpty ? nil : roomID, lastConfirmedAt: Date(), preparationKind: kind.preparationKind))
        quantityText = ""; ready = nil; reachable = nil; editingQuantity = false
    }

    private func amount(_ value: Double, unit: String) -> String {
        let l = model.localizer
        switch unit {
        case "usGallon", "gal": return ServiceNames.quantity(value, unit: "gal", localizer: l, countryCode: model.household?.privateLocation?.countryCode)
        // Core computes the water requirement in litres; shown in the household's usual units.
        case "liter": return ServiceNames.quantity(value / 3.785411784, unit: "gal", localizer: l, countryCode: model.household?.privateLocation?.countryCode)
        default: return "\(PlanFormatting.number(value, locale: model.locale)) \(l("inventory.unit.\(unit)"))"
        }
    }
}
