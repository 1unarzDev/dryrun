import SwiftUI
import DryRunCore

/// Prepare → What to buy: Core's household-sized list with planning price ranges. Checking an item off records it as
/// confirmed inventory, so gaps, the Prepare list and the score update; nothing is purchased or sent anywhere.
struct ShoppingListView: View {
    @Environment(AppModel.self) private var model
    @State private var complete = false
    @State private var budget = 150.0
    @State private var saving: String?

    var body: some View {
        let l = model.localizer
        let ranked = model.shoppingItems
        let shown = complete ? ranked : ShoppingList.kit(ranked, .budget(limit: budget))
        let total = ShoppingList.total(shown)
        List {
            Section {
                Text(l("shop.intro")).font(.callout)
                Picker("", selection: $complete) {
                    Text(l("shop.kit.budget")).tag(false)
                    Text(l("shop.kit.complete")).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shop.kit")
                if !complete {
                    Stepper(l("shop.budget", ["amount": money(budget)]), value: $budget, in: 50...2000, step: 50)
                        .accessibilityIdentifier("shop.budget")
                }
                LabeledContent(l("shop.total", ["low": money(total.low), "high": money(total.high)]), value: "")
                    .font(.headline)
                    .accessibilityIdentifier("shop.total")
                if !complete, shown.count < ranked.count {
                    Text(l("shop.skipped", ["count": "\(ranked.count - shown.count)"])).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if ranked.isEmpty {
                Section { Text(l("shop.empty")) }
            }
            ForEach([ShoppingList.Tier.medical, .lifeSafety, .basics], id: \.self) { tier in
                let items = shown.filter { $0.tier == tier }
                if !items.isEmpty {
                    Section(l("shop.tier.\(tierKey(tier))")) {
                        ForEach(items) { row($0) }
                    }
                }
            }
            if let prices = model.priceTable {
                Section { Text(l("shop.prices", ["date": prices.retrievedAt])).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(l("shop.title"))
    }

    private func row(_ item: ShoppingList.Item) -> some View {
        let l = model.localizer
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(l("shop.item.\(item.priceID)")).font(.headline)
                Spacer()
                Text("\(money(item.low))–\(money(item.high))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(l("shop.qty.\(item.unit)", ["count": item.quantity.formatted(.number.precision(.fractionLength(0)))]))
                .font(.subheadline.weight(.semibold))
            Text(model.shoppingReason(item)).font(.footnote).foregroundStyle(.secondary)
            Button {
                saving = item.id
                Task { _ = await model.markBought(item); saving = nil }
            } label: {
                Label(l("shop.markBought"), systemImage: "checkmark.circle")
                    .frame(minHeight: Theme.minTap)
            }
            .buttonStyle(.borderless)
            .disabled(saving != nil)
            .accessibilityIdentifier("shop.buy.\(item.priceID)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shop.item.\(item.priceID)")
    }

    private func tierKey(_ tier: ShoppingList.Tier) -> String {
        switch tier { case .medical: "medical"; case .lifeSafety: "lifeSafety"; case .basics: "basics" }
    }

    private func money(_ value: Double) -> String { value.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
}

/// The Prepare entry to the list, with this household's Budget-kit estimate.
struct ShoppingEntryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let l = model.localizer
        let items = model.shoppingItems
        NavigationLink { ShoppingListView() } label: {
            SectionCard(title: l("shop.open"), systemImage: "cart.fill") {
                Text(l("shop.intro")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                if let first = items.first {
                    Label(l("shop.item.\(first.priceID)"), systemImage: first.tier == .medical ? "cross.case.fill" : "1.circle")
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("next.shopping")
    }
}
