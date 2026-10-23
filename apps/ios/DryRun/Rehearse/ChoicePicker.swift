import SwiftUI
import DryRunCore

/// One option a screen offers. Built from Core/authored data only (hazard commands the host validated, authored
/// decision options, household records); the picker never decides which option is right and never styles one so.
struct ChoiceItem: Hashable {
    /// Accessibility identifier, kept exactly as before (`rehearsal.cmd.*`, `decision.option.*`) so UI tests still match.
    let id: String
    let title: String
    let symbol: String
    /// First level: what kind of action (`HazardChoice.Purpose` raw value or command kind).
    var group: String = "other"
    /// Second level: who acts or is helped.
    var personID: String?
    var personLabel: String?
    /// Final level: a short destination shown on the chip; the full title stays the accessibility label.
    var place: String?
    /// Row identity: generic options can share an accessibility identifier, never a title.
    var key: String { id + "|" + title }
}

/// English-first copy for the picker's own headings. A `choice.*` key is used when a locale table carries it;
/// otherwise the English text shows, so adding a heading never makes a translated locale incomplete.
enum ChoiceCopy {
    static func text(_ english: String, key: String, localizer l: Localizer) -> String {
        let resolved = l.text("choice.\(key)")
        return resolved.isMissing ? english : resolved.text
    }

    static func group(_ id: String, localizer l: Localizer) -> (title: String, symbol: String) {
        let (english, symbol): (String, String) = {
            switch id {
            case "escape": return ("Get out", "figure.walk.departure")
            case "accompanyEscape": return ("Help someone out", "figure.2")
            case "accountOutside": return ("Check in outside", "checklist")
            case "shelter": return ("Take shelter", "shield.lefthalf.filled")
            case "accompanyShelter": return ("Help to shelter", "figure.2.arms.open")
            case "refuge": return ("Go higher", "stairs")
            case "depart": return ("Leave", "car")
            case "warmth": return ("Stay warm", "thermometer.snowflake")
            case "shade": return ("Block the sun", "blinds.horizontal.closed")
            case "moveToShade": return ("Move somewhere cooler", "figure.walk")
            case "gather": return ("Gather together", "person.3")
            case "power", "allocatePower": return ("Power", "bolt")
            case "contact": return ("Call someone", "phone")
            case "water", "useStoredWater": return ("Water", "drop")
            case "carrySupply": return ("Carry supplies", "shippingbox")
            case "placeSupply": return ("Place supplies", "tray.and.arrow.down")
            case "recognizeGap": return ("Notice a gap", "questionmark.circle")
            case "assignHelper": return ("Pair a helper", "figure.2")
            case "closeDoor": return ("Close a door", "door.left.hand.closed")
            default: return ("Other", "ellipsis.circle")
            }
        }()
        return (text(english, key: "group.\(id)", localizer: l), symbol)
    }
}

/// Never more than `flatLimit` flat options. When a moment offers more (hazard commands multiply person x room x
/// action), the choice narrows in place: what kind of action, then who (avatar chips), then where (destination
/// chips). The final chip keeps the option's accessibility identifier and commits it with one tap, as before.
struct ChoicePicker: View {
    @Environment(AppModel.self) private var model
    let items: [ChoiceItem]
    var disabled = false
    let onChoose: (ChoiceItem) -> Void

    static let flatLimit = 5
    @State private var group: String?
    @State private var person: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if items.count <= Self.flatLimit {
                ForEach(items, id: \.key) { row($0) }
            } else {
                grouped
            }
        }
    }

    // MARK: Levels

    @ViewBuilder private var grouped: some View {
        let l = model.localizer
        let groups = ordered(items.map(\.group))
        let currentGroup = group.flatMap { groups.contains($0) ? $0 : nil } ?? groups.first
        let inGroup = items.filter { $0.group == currentGroup }
        let people = ordered(inGroup.compactMap(\.personID))
        let currentPerson = person.flatMap { people.contains($0) ? $0 : nil } ?? people.first
        let leaves = people.count > 1 ? inGroup.filter { $0.personID == currentPerson || $0.personID == nil } : inGroup

        if groups.count > 1 {
            step(ChoiceCopy.text("What", key: "step.what", localizer: l), number: 1)
            chipGrid(groups, limit: 6) { id in
                let meta = ChoiceCopy.group(id, localizer: l)
                let count = items.filter { $0.group == id }.count
                return ChoiceChip(title: meta.title, symbol: meta.symbol, badge: count > 1 ? "\(count)" : nil,
                                  selected: id == currentGroup, identifier: "choice.group.\(id)") {
                    group = id; person = nil
                }
            }
        }
        if people.count > 1 {
            step(ChoiceCopy.text("Who", key: "step.who", localizer: l), number: groups.count > 1 ? 2 : 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(people, id: \.self) { id in
                        let label = inGroup.first { $0.personID == id }?.personLabel ?? id
                        PersonChip(label: label, selected: id == currentPerson, identifier: "choice.person.\(currentGroup ?? "").\(id)") {
                            person = id
                        }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
        if groups.count > 1 || people.count > 1 {
            step(ChoiceCopy.text("Choose one", key: "step.which", localizer: l), number: (groups.count > 1 ? 1 : 0) + (people.count > 1 ? 1 : 0) + 1)
        }
        leafList(leaves, compact: people.count > 1)
    }

    @ViewBuilder private func leafList(_ leaves: [ChoiceItem], compact: Bool) -> some View {
        let l = model.localizer
        let shown = leaves.count <= Self.flatLimit ? leaves : Array(leaves.prefix(Self.flatLimit - 1))
        let more = leaves.count <= Self.flatLimit ? [] : Array(leaves.dropFirst(Self.flatLimit - 1))
        ForEach(shown, id: \.key) { row($0, compact: compact) }
        if !more.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Theme.Space.s) { ForEach(more, id: \.key) { row($0, compact: compact) } }
                    .padding(.top, Theme.Space.s)
            } label: {
                Label(ChoiceCopy.text("More (\(more.count))", key: "more", localizer: l), systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("choice.more")
        }
    }

    /// The final option: one tap commits. With a person chosen above, the chip leads with the destination.
    private func row(_ item: ChoiceItem, compact: Bool = false) -> some View {
        Button { onChoose(item) } label: {
            if compact, let place = item.place {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: item.symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place).font(.body.weight(.semibold))
                        Text(item.title).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            } else {
                Label {
                    Text(item.title).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: item.symbol).foregroundStyle(Theme.accent)
                }
                .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.choice)
        .disabled(disabled)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier(item.id)
    }

    // MARK: Pieces

    private func step(_ title: String, number: Int) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20).background(Theme.accent, in: Circle())
            Text(title).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .padding(.top, Theme.Space.xs)
    }

    @ViewBuilder private func chipGrid(_ ids: [String], limit: Int, chip: @escaping (String) -> ChoiceChip) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.s)], alignment: .leading, spacing: Theme.Space.s) {
            ForEach(ids, id: \.self) { chip($0) }
        }
    }

    private func ordered(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// A selectable chip: icon + text, selected state by fill, outline and a checkmark (never color alone).
struct ChoiceChip: View {
    let title: String
    let symbol: String
    var badge: String?
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : symbol)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge).font(.caption.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.surface, in: Capsule())
                }
            }
            .foregroundStyle(selected ? Theme.accent : Theme.ink)
            .padding(.horizontal, Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: Theme.comfortableTap, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.14) : Theme.surfaceMuted.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// A household member as an avatar chip (initials in a circle, then the name).
struct PersonChip: View {
    let label: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Text(Self.initials(label)).font(.footnote.weight(.bold))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(selected ? Theme.accent : Theme.accent.opacity(0.14), in: Circle())
                Text(label).font(.subheadline.weight(.semibold)).lineLimit(1)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            }
            .foregroundStyle(selected ? Theme.accent : Theme.ink)
            .padding(.leading, Theme.Space.xs).padding(.trailing, Theme.Space.m)
            .frame(minHeight: Theme.comfortableTap)
            .background(selected ? Theme.accent.opacity(0.14) : Theme.surfaceMuted.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    static func initials(_ label: String) -> String {
        let words = label.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// "Move someone": person avatar chips, then room chips, then one confirm button. Replaces two menu pickers.
struct PersonRoomPicker: View {
    @Environment(AppModel.self) private var model
    let people: [Person]
    let home: HomeModel
    @Binding var personID: String
    @Binding var roomID: String
    let confirmIdentifier: String
    var canConfirm: Bool
    let onConfirm: () -> Void

    var body: some View {
        let l = model.localizer
        let rooms = home.spaces
        let shown = rooms.count <= 6 || showAllRooms ? rooms : Array(rooms.prefix(5))
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(l("adaptive.movePerson")).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(people) { person in
                        PersonChip(label: person.localizedLabel(l), selected: personID == person.id,
                                   identifier: "choice.movePerson.\(person.id)") { personID = person.id }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
            Text(l("adaptive.moveRoom")).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.s)], alignment: .leading, spacing: Theme.Space.s) {
                ForEach(shown) { room in
                    ChoiceChip(title: HomeScenePresentation.roomLabel(room.id, in: home), symbol: "square.split.bottomrightquarter",
                               selected: roomID == room.id, identifier: "choice.moveRoom.\(room.id)") { roomID = room.id }
                }
            }
            if shown.count < rooms.count {
                Button(ChoiceCopy.text("More rooms (\(rooms.count - shown.count))", key: "moreRooms", localizer: l)) { showAllRooms = true }
                    .buttonStyle(.plain).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(minHeight: Theme.minTap)
                    .accessibilityIdentifier("choice.moreRooms")
            }
            Button(l("adaptive.moveGo"), action: onConfirm)
                .buttonStyle(.secondary)
                .disabled(!canConfirm)
                .accessibilityIdentifier(confirmIdentifier)
        }
    }

    @State private var showAllRooms = false
}

extension ExerciseActions.Option {
    /// The picker's view of this option, with the person's display name for avatar chips.
    func choiceItem(_ household: HouseholdProfile, localizer l: Localizer) -> ChoiceItem {
        ChoiceItem(id: identifier, title: title, symbol: symbol, group: group, personID: personID,
                   personLabel: personID.flatMap { id in household.people.first { $0.id == id }?.localizedLabel(l) },
                   place: place)
    }
}
