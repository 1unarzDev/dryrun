import Foundation

/// "Describe your family in your own words": what Dry Run understood, before the family confirms any of it.
///
/// A proposal only ever holds structured choices the app already offers (age band, relationship, assistance needs,
/// equipment purpose, pets, housing). It never holds clinical free text, medication names, phone numbers or
/// addresses, never marks anything confirmed, and is applied only after the family reviews it. The same type is
/// produced by the optional on-device language model and by the keyword reader used when no model is available.
public struct IntakeProposal: Codable, Sendable, Hashable {
    public enum Source: String, Codable, Sendable, Hashable { case onDeviceModel, keywords }

    public struct PersonDraft: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        /// The family's own word ("Mom", "Abuela", "Ông") or a first name they typed. Never a diagnosis.
        public var alias: String
        public var ageBand: AgeBand
        public var relationship: FamilyRelationship?
        public var needs: [AssistanceNeed]
        /// The person describing the household.
        public var isSelf: Bool
        public init(id: String, alias: String = "", ageBand: AgeBand = .unknown, relationship: FamilyRelationship? = nil,
                    needs: [AssistanceNeed] = [], isSelf: Bool = false) {
            self.id = id; self.alias = alias; self.ageBand = ageBand; self.relationship = relationship
            self.needs = needs; self.isSelf = isSelf
        }
    }

    public struct EquipmentDraft: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var purpose: EquipmentPurpose
        /// A `PersonDraft.id` in the same proposal, when the description said who uses it.
        public var personID: String?
        public init(id: String, purpose: EquipmentPurpose, personID: String? = nil) {
            self.id = id; self.purpose = purpose; self.personID = personID
        }
    }

    public struct PetDraft: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var kind: PetKind
        public var count: Int
        public init(id: String, kind: PetKind, count: Int = 1) { self.id = id; self.kind = kind; self.count = count }
    }

    public var people: [PersonDraft]
    public var equipment: [EquipmentDraft]
    public var pets: [PetDraft]
    public var homeType: HomeType?
    public var tenancy: Tenancy?
    public var heatingFuel: HeatingFuel?
    public var cooling: CoolingKind?
    public var waterSource: WaterSourceKind?
    public var floorCount: Int?
    public var source: Source

    public init(people: [PersonDraft] = [], equipment: [EquipmentDraft] = [], pets: [PetDraft] = [],
                homeType: HomeType? = nil, tenancy: Tenancy? = nil, heatingFuel: HeatingFuel? = nil,
                cooling: CoolingKind? = nil, waterSource: WaterSourceKind? = nil, floorCount: Int? = nil,
                source: Source) {
        self.people = people; self.equipment = equipment; self.pets = pets
        self.homeType = homeType; self.tenancy = tenancy; self.heatingFuel = heatingFuel; self.cooling = cooling
        self.waterSource = waterSource; self.floorCount = floorCount; self.source = source
    }

    /// Nothing understood beyond the (always present) speaker.
    public var isEmpty: Bool {
        people.allSatisfy { $0.isSelf && $0.needs.isEmpty && $0.ageBand == .unknown && $0.alias.isEmpty }
            && equipment.isEmpty && pets.isEmpty && homeType == nil && tenancy == nil && heatingFuel == nil
            && cooling == nil && waterSource == nil && floorCount == nil
    }

    /// Bounds and de-duplicates whatever produced the proposal (a model can repeat itself or overcount).
    public func sanitized() -> IntakeProposal {
        var out = self
        var selfSeen = false
        out.people = people.prefix(HouseholdIntake.maxPeople).compactMap { p in
            var p = p
            p.alias = String(p.alias.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            p.needs = p.needs.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            if p.isSelf { if selfSeen { return nil }; selfSeen = true; p.relationship = nil }
            return p
        }
        let personIDs = Set(out.people.map(\.id))
        var seenEquipment = Set<String>()
        out.equipment = equipment.prefix(HouseholdIntake.maxEquipment).compactMap { e in
            var e = e
            if let id = e.personID, !personIDs.contains(id) { e.personID = nil }
            let key = "\(e.purpose.rawValue)|\(e.personID ?? "")"
            return seenEquipment.insert(key).inserted ? e : nil
        }
        var seenPets = Set<PetKind>()
        out.pets = pets.compactMap { p in
            guard seenPets.insert(p.kind).inserted else { return nil }
            var p = p; p.count = min(max(p.count, 1), 20); return p
        }
        if let f = floorCount, !(1...5).contains(f) { out.floorCount = nil }
        return out
    }
}

public enum HouseholdIntake {
    public static let maxPeople = 12
    public static let maxEquipment = 12

    // MARK: Apply

    /// Merges a reviewed proposal into a draft. Facts the family already entered win: a set home type, a named
    /// person's age band or an existing device is never overwritten. Everything added stays unconfirmed.
    public static func apply(_ proposal: IntakeProposal, to h: inout HouseholdProfile, makeID: () -> String = { String(UUID().uuidString.prefix(8)).lowercased() }) {
        let p = proposal.sanitized()
        var personMap: [String: String] = [:]
        for draft in p.people {
            if draft.isSelf, let i = h.people.firstIndex(where: { $0.isSelf == true }) ?? (h.people.isEmpty ? nil : 0) {
                merge(draft, into: &h.people[i]); personMap[draft.id] = h.people[i].id
                continue
            }
            let alias = draft.alias.lowercased()
            if !alias.isEmpty, let i = h.people.firstIndex(where: { $0.alias.lowercased() == alias }) {
                merge(draft, into: &h.people[i]); personMap[draft.id] = h.people[i].id
                continue
            }
            guard h.people.count < maxPeople else { continue }
            let person = Person(id: "p-\(makeID())", alias: draft.alias, ageBand: draft.ageBand, needs: draft.needs,
                                relationship: draft.relationship)
            h.people.append(person); personMap[draft.id] = person.id
        }
        for draft in p.equipment {
            let personID = draft.personID.flatMap { personMap[$0] }
            guard !h.equipment.contains(where: { $0.purpose == draft.purpose && $0.personID == personID }) else { continue }
            h.equipment.append(PoweredEquipment(id: "eq-\(makeID())", purpose: draft.purpose, label: "", personID: personID))
        }
        for draft in p.pets where !h.pets.contains(where: { $0.kind == draft.kind }) {
            h.pets.append(Pet(id: "pet-\(makeID())", kind: draft.kind, count: draft.count))
        }
        if let v = p.homeType, h.housing.homeType == .other { h.housing.homeType = v }
        if let v = p.tenancy, h.housing.tenancy == .other { h.housing.tenancy = v }
        if let v = p.heatingFuel, h.housing.heatingFuel == .unknown { h.housing.heatingFuel = v }
        if let v = p.cooling, h.housing.cooling == .unknown { h.housing.cooling = v }
        if let v = p.waterSource, h.housing.waterSource == .unknown { h.housing.waterSource = v }
        if let v = p.floorCount, h.housing.floorCount <= 1 { h.housing.floorCount = v }
    }

    private static func merge(_ draft: IntakeProposal.PersonDraft, into person: inout Person) {
        if person.alias.trimmingCharacters(in: .whitespaces).isEmpty { person.alias = draft.alias }
        if person.ageBand == .unknown { person.ageBand = draft.ageBand }
        if person.relationship == nil, person.isSelf != true { person.relationship = draft.relationship }
        for need in draft.needs where !person.needs.contains(need) { person.needs.append(need) }
    }

    // MARK: Grounding

    /// Combines a language model's reading with the keyword reader's. The model is good at who is who and at free
    /// phrasing; it can also invent. Medical facts (assistance needs and equipment) are therefore kept only when the
    /// family's own words support them: a need or device the model proposes survives only if the keyword reader
    /// found the same need or device somewhere in the text, and anything the keyword reader found that the model
    /// missed is added for the matching person. People, pets and home details come from the model.
    public static func ground(model: IntakeProposal, keywords: IntakeProposal) -> IntakeProposal {
        var out = model.sanitized()
        let kw = keywords.sanitized()
        let groundedNeeds = Set(kw.people.flatMap(\.needs))
        let groundedPurposes = Set(kw.equipment.map(\.purpose))
        for i in out.people.indices { out.people[i].needs.removeAll { !groundedNeeds.contains($0) } }
        out.equipment.removeAll { !groundedPurposes.contains($0.purpose) }

        /// The model's person matching a keyword person: the speaker, then same name, then same relationship.
        func match(_ k: IntakeProposal.PersonDraft?) -> String? {
            guard let k else { return nil }
            if k.isSelf { return out.people.first(where: \.isSelf)?.id }
            if !k.alias.isEmpty, let p = out.people.first(where: { $0.alias.lowercased() == k.alias.lowercased() }) { return p.id }
            if let r = k.relationship, let p = out.people.first(where: { $0.relationship == r }) { return p.id }
            return nil
        }
        for k in kw.people {
            let target = match(k) ?? (k.needs.isEmpty ? nil : out.people.first(where: \.isSelf)?.id)
            guard let target, let i = out.people.firstIndex(where: { $0.id == target }) else { continue }
            for need in k.needs where !out.people[i].needs.contains(need) { out.people[i].needs.append(need) }
        }
        for e in kw.equipment where !out.equipment.contains(where: { $0.purpose == e.purpose }) {
            let owner = match(kw.people.first { $0.id == e.personID })
            out.equipment.append(.init(id: "kw-\(e.id)", purpose: e.purpose, personID: owner))
        }
        return out.sanitized()
    }

    // MARK: Keyword reader

    /// Reads a short description without any model: explicit words only, in English, Spanish or Vietnamese.
    /// Used whenever the on-device model is unavailable, so every iPhone gets the same kind of head start.
    public static func keywordProposal(from text: String) -> IntakeProposal {
        let vietnamese = Lexicon.looksVietnamese(text)
        let clauses = text
            .components(separatedBy: CharacterSet(charactersIn: ".;!?\n,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Lexicon.Clause($0, isVietnamese: vietnamese) }
        var proposal = IntakeProposal(people: [IntakeProposal.PersonDraft(id: "self", isSelf: true)], source: .keywords)
        var relationshipPeople: [String: String] = [:]   // lexicon key -> draft id: one "Mom" however often she is mentioned
        var lastPerson: String?                          // for "She uses oxygen" after "My mom lives with us"
        var counter = 0
        func nextID(_ prefix: String) -> String { counter += 1; return "\(prefix)\(counter)" }

        for clause in clauses {
            var used: [Range<Int>] = []   // character offsets already read as a person ("ông bà" is not also "ông")
            func fresh(_ m: Lexicon.Match) -> Bool {
                let lo = m.haystack.distance(from: m.haystack.startIndex, to: m.range.lowerBound)
                let span = lo..<(lo + m.haystack[m.range].count)
                guard !used.contains(where: { $0.overlaps(span) }) else { return false }
                used.append(span); return true
            }
            func find(_ terms: [String]) -> Lexicon.Match? {
                guard let m = Lexicon.firstMatch(terms, in: clause), !Lexicon.isNegated(m) else { return nil }
                return m
            }
            var clausePeople: [String] = []
            for entry in Lexicon.people {
                guard let match = find(entry.terms), fresh(match) else { continue }
                if !entry.plural, let existing = relationshipPeople[entry.key] { clausePeople.append(existing); continue }
                let count = entry.plural ? min(Lexicon.count(before: match) ?? entry.defaultCount, 6) : 1
                for i in 0..<max(count, 1) {
                    let draft = IntakeProposal.PersonDraft(id: nextID("p"), alias: entry.plural ? "" : Lexicon.display(match.text),
                                                           ageBand: entry.ageBand, relationship: entry.relationship)
                    proposal.people.append(draft); clausePeople.append(draft.id)
                    if !entry.plural, i == 0 { relationshipPeople[entry.key] = draft.id }
                }
            }
            let speaksForSelf = Lexicon.firstMatch(Lexicon.firstPerson, in: clause) != nil
            let refersBack = Lexicon.firstMatch(Lexicon.thirdPerson, in: clause) != nil
            // Needs and equipment belong to the one person the clause names; else to the speaker ("I use a walker");
            // else, after "she"/"he"/"ella", to the person named just before. Otherwise equipment stays unassigned.
            let owner: String? = clausePeople.count == 1 ? clausePeople[0]
                : clausePeople.isEmpty ? (speaksForSelf ? "self" : refersBack ? lastPerson : nil) : nil
            for entry in Lexicon.needs {
                guard find(entry.terms) != nil, clausePeople.count <= 1 else { continue }   // several people named: do not guess who
                let target = owner ?? lastPerson ?? "self"
                if let i = proposal.people.firstIndex(where: { $0.id == target }), !proposal.people[i].needs.contains(entry.need) {
                    proposal.people[i].needs.append(entry.need)
                }
            }
            for entry in Lexicon.equipment where find(entry.terms) != nil {
                proposal.equipment.append(.init(id: nextID("eq"), purpose: entry.purpose, personID: owner))
            }
            for entry in Lexicon.pets {
                guard let match = find(entry.terms), fresh(match) else { continue }
                proposal.pets.append(.init(id: nextID("pet"), kind: entry.kind, count: Lexicon.count(before: match) ?? (entry.plural ? 2 : 1)))
            }
            func pick<T>(_ table: [(T, [String])]) -> T? { table.first { find($0.1) != nil }?.0 }
            proposal.homeType = proposal.homeType ?? pick(Lexicon.homeTypes)
            proposal.tenancy = proposal.tenancy ?? pick(Lexicon.tenancy)
            proposal.heatingFuel = proposal.heatingFuel ?? pick(Lexicon.heating)
            proposal.waterSource = proposal.waterSource ?? pick(Lexicon.water)
            proposal.cooling = proposal.cooling ?? pick(Lexicon.cooling)
            if clausePeople.count == 1 { lastPerson = clausePeople[0] }
        }
        return proposal.sanitized()
    }
}

// MARK: - Lexicon (explicit words only; extend with care and add a test for every new word)

/// Terms are English/Spanish unless written `vi:`. English and Spanish match without regard to accents ("oxigeno" =
/// "oxígeno"). Vietnamese terms keep their tone marks and match only in Vietnamese text, because removing marks
/// merges different words (mẹ "mother" would become the English "me").
enum Lexicon {
    struct Match { let range: Range<String.Index>; let text: String; let haystack: String }

    /// One clause, prepared once: the folded English/Spanish view and, for Vietnamese text, the original.
    struct Clause {
        let folded: String
        let original: String
        let isVietnamese: Bool
        init(_ text: String, isVietnamese: Bool) {
            original = text.lowercased(); folded = Lexicon.fold(text); self.isVietnamese = isVietnamese
        }
    }

    struct PersonEntry { let key: String; let terms: [String]; let relationship: FamilyRelationship; let ageBand: AgeBand; let plural: Bool; let defaultCount: Int }
    static func person(_ key: String, _ terms: [String], _ r: FamilyRelationship, _ age: AgeBand = .unknown, plural: Bool = false, defaultCount: Int = 2) -> PersonEntry {
        PersonEntry(key: key, terms: terms, relationship: r, ageBand: age, plural: plural, defaultCount: defaultCount)
    }
    // Plural and longer entries come first so "grandparents" is not also one "grandparent", and "bà nội" wins over "bà".
    static let people: [PersonEntry] = [
        person("grandparents", ["grandparents", "abuelos", "vi:ông bà"], .grandparent, plural: true),
        person("parents", ["my parents", "mis padres", "vi:bố mẹ", "vi:cha mẹ"], .parent, plural: true),
        person("children", ["kids", "children", "sons", "daughters", "hijos", "hijas", "niños", "niñas", "vi:các con"], .child, .child, plural: true),
        person("grandmother", ["grandma", "grandmother", "granny", "abuela", "abuelita", "vi:bà nội", "vi:bà ngoại", "vi:bà"], .grandparent),
        person("grandfather", ["grandpa", "grandfather", "abuelo", "abuelito", "vi:ông nội", "vi:ông ngoại", "vi:ông"], .grandparent),
        person("mother", ["mom", "mother", "mum", "mama", "mamá", "madre", "vi:mẹ", "vi:má"], .mother),
        person("father", ["dad", "father", "papa", "papá", "padre", "vi:bố", "vi:cha"], .father),
        person("spouse", ["wife", "husband", "partner", "spouse", "esposa", "esposo", "marido", "pareja", "vi:vợ", "vi:chồng"], .spousePartner),
        person("infant", ["baby", "infant", "newborn", "bebé", "vi:em bé"], .child, .infant),
        person("teen", ["teen", "teenager", "adolescente"], .child, .teen),
        person("son", ["son", "hijo", "vi:con trai"], .child),
        person("daughter", ["daughter", "hija", "vi:con gái"], .child),
        person("child", ["kid", "child", "niño", "niña"], .child, .child),
        person("brother", ["brother", "hermano", "vi:anh trai", "vi:em trai"], .sibling),
        person("sister", ["sister", "hermana", "vi:chị gái", "vi:em gái"], .sibling),
        person("aunt", ["aunt", "tía"], .aunt),
        person("uncle", ["uncle", "tío"], .uncle),
        person("caregiver", ["caregiver", "home health aide", "cuidadora", "cuidador", "vi:người chăm sóc"], .caregiver),
    ]

    static let firstPerson = ["i", "i'm", "im", "myself", "yo", "vi:tôi", "vi:mình"]
    static let thirdPerson = ["she", "he", "her", "his", "they", "ella", "ellos", "vi:bà ấy", "vi:ông ấy", "vi:cô ấy", "vi:anh ấy"]

    struct NeedEntry { let need: AssistanceNeed; let terms: [String] }
    static let needs: [NeedEntry] = [
        .init(need: .usesWheelchair, terms: ["wheelchair", "silla de ruedas", "vi:xe lăn"]),
        .init(need: .cannotUseStairs, terms: ["can't do stairs", "cannot do stairs", "can't use stairs", "cannot use stairs", "can't climb stairs", "no puede subir escaleras", "vi:không leo cầu thang"]),
        .init(need: .limitedMobility, terms: ["walker", "cane", "trouble walking", "hard time walking", "bedridden", "bedbound", "andadera", "andador", "bastón", "encamado", "encamada", "vi:khó đi lại", "vi:nằm liệt giường"]),
        .init(need: .needsHelperToEvacuate, terms: ["bedridden", "bedbound", "encamado", "encamada", "vi:nằm liệt giường", "needs help to get out", "necesita ayuda para salir"]),
        .init(need: .deafOrHardOfHearing, terms: ["deaf", "hard of hearing", "hearing aid", "hearing aids", "sordo", "sorda", "audífono", "audífonos", "vi:điếc", "vi:máy trợ thính", "vi:khiếm thính"]),
        .init(need: .blindOrLowVision, terms: ["blind", "low vision", "ciego", "ciega", "baja visión", "vi:khiếm thị"]),
        .init(need: .cognitiveOrMemory, terms: ["dementia", "alzheimer", "alzheimer's", "memory loss", "demencia", "pérdida de memoria", "vi:sa sút trí tuệ", "vi:mất trí nhớ"]),
        .init(need: .communicationSupport, terms: ["nonverbal", "non-verbal", "sign language", "asl", "lenguaje de señas", "no verbal", "vi:ngôn ngữ ký hiệu"]),
    ]

    struct EquipmentEntry { let purpose: EquipmentPurpose; let terms: [String] }
    static let equipment: [EquipmentEntry] = [
        .init(purpose: .oxygenConcentrator, terms: ["oxygen", "o2", "concentrator", "oxígeno", "vi:máy oxy", "vi:bình oxy", "vi:thở oxy"]),
        .init(purpose: .cpapOrBipap, terms: ["cpap", "bipap", "sleep apnea", "apnea del sueño", "vi:máy thở"]),
        .init(purpose: .powerWheelchair, terms: ["power wheelchair", "electric wheelchair", "motorized wheelchair", "power chair", "silla de ruedas eléctrica", "vi:xe lăn điện"]),
        .init(purpose: .refrigeratedMedication, terms: ["insulin", "insulina", "refrigerated medicine", "refrigerated medication", "medicina refrigerada", "medicamento refrigerado", "vi:thuốc cần để lạnh"]),
        .init(purpose: .homeDialysis, terms: ["dialysis", "diálisis", "vi:lọc máu", "vi:chạy thận"]),
        .init(purpose: .suction, terms: ["suction machine", "suction", "succión", "vi:máy hút đàm"]),
        .init(purpose: .feedingPump, terms: ["feeding pump", "feeding tube", "g-tube", "g tube", "bomba de alimentación", "sonda de alimentación", "vi:ống thông dạ dày"]),
    ]

    struct PetEntry { let kind: PetKind; let terms: [String]; let plural: Bool }
    static let pets: [PetEntry] = [
        .init(kind: .dog, terms: ["dogs", "perros"], plural: true),
        .init(kind: .dog, terms: ["dog", "puppy", "perro", "perrito", "perrita", "vi:chó"], plural: false),
        .init(kind: .cat, terms: ["cats", "gatos"], plural: true),
        .init(kind: .cat, terms: ["cat", "kitten", "gato", "gatito", "gata", "vi:mèo"], plural: false),
        .init(kind: .bird, terms: ["bird", "birds", "parrot", "pájaro", "pájaros", "loro", "vi:chim", "vi:vẹt"], plural: false),
        .init(kind: .smallAnimal, terms: ["hamster", "rabbit", "bunny", "guinea pig", "conejo", "hámster", "vi:thỏ"], plural: false),
    ]

    static let homeTypes: [(HomeType, [String])] = [
        (.manufacturedHome, ["mobile home", "manufactured home", "trailer", "casa móvil", "traila", "vi:nhà di động"]),
        (.apartment, ["apartment", "apt", "condo", "apartamento", "departamento", "vi:chung cư", "vi:căn hộ"]),
        (.townhouse, ["townhouse", "townhome", "casa adosada"]),
        (.duplex, ["duplex", "dúplex"]),
        (.singleFamily, ["single-family", "single family"]),
    ]
    static let tenancy: [(Tenancy, [String])] = [
        (.renter, ["rent", "renting", "renter", "rental", "lease", "alquilamos", "alquiler", "rentamos", "rentando", "vi:thuê"]),
        (.owner, ["we own", "i own", "own our", "own my", "homeowner", "somos dueños", "casa propia"]),
    ]
    static let heating: [(HeatingFuel, [String])] = [
        (.naturalGas, ["gas heat", "natural gas", "gas furnace", "calefacción de gas", "vi:sưởi bằng gas"]),
        (.electric, ["electric heat", "heat pump", "calefacción eléctrica", "vi:sưởi điện"]),
        (.propane, ["propane", "propano"]),
        (.wood, ["wood stove", "fireplace", "leña", "vi:lò củi"]),
    ]
    static let water: [(WaterSourceKind, [String])] = [
        (.privateWell, ["well water", "private well", "water well", "agua de pozo", "pozo", "vi:nước giếng", "vi:giếng"]),
        (.municipal, ["city water", "agua de la ciudad", "vi:nước máy"]),
    ]
    static let cooling: [(CoolingKind, [String])] = [
        (.fansOnly, ["only fans", "just fans", "no ac", "no a/c", "no air conditioning", "solo ventiladores", "sin aire", "vi:chỉ có quạt", "vi:không có máy lạnh"]),
        (.windowOrPortableAC, ["window unit", "window ac", "portable ac", "aire de ventana", "vi:máy lạnh cửa sổ"]),
        (.centralAC, ["central air", "central ac", "aire central"]),
    ]

    /// Phrases that already state an absence are not themselves "negated" (`no ac` means fans only).
    static let negations: Set<String> = ["no", "not", "don't", "dont", "doesn't", "doesnt", "never", "without", "sin", "ni", "nunca", "khong", "chua"]

    /// Letters used by Vietnamese and not by English or Spanish.
    static let vietnameseLetters = Set("ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ")
    static func looksVietnamese(_ text: String) -> Bool { text.lowercased().contains { vietnameseLetters.contains($0) } }

    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func firstMatch(_ terms: [String], in clause: Clause) -> Match? {
        for term in terms {
            if term.hasPrefix("vi:") {
                guard clause.isVietnamese else { continue }
                let t = String(term.dropFirst(3))
                if let r = wordRange(of: t, in: clause.original) { return Match(range: r, text: String(clause.original[r]), haystack: clause.original) }
            } else if let r = wordRange(of: fold(term), in: clause.folded) {
                return Match(range: r, text: term, haystack: clause.folded)
            }
        }
        return nil
    }

    /// A whole-word occurrence: letters may not continue on either side ("cane" is not in "hurricane").
    static func wordRange(of term: String, in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while start < text.endIndex, let r = text.range(of: term, range: start..<text.endIndex) {
            let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return r }
            start = text.index(after: r.lowerBound)
        }
        return nil
    }

    /// "no pets", "we don't have a dog", "sin perro", "không có chó": a negation within the three words before.
    static func isNegated(_ match: Match) -> Bool {
        let words = match.haystack[..<match.range.lowerBound].split(separator: " ").suffix(3).map { fold(String($0)) }
        return words.contains { negations.contains($0) }
    }

    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "both": 2,
        "un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
        "mot": 1, "hai": 2, "bon": 4, "sau": 6,
    ]
    static let countFillers: Set<String> = ["con", "đứa", "dua", "my", "our", "mis", "nuestros", "nuestras", "little", "small", "big", "old", "young"]
    /// A count stated just before the match ("two kids", "3 dogs", "dos perros", "hai con mèo").
    static func count(before match: Match) -> Int? {
        let words = match.haystack[..<match.range.lowerBound].split(separator: " ").suffix(3).map { fold(String($0)) }
            .filter { !countFillers.contains($0) }
        guard let last = words.last else { return nil }
        if let n = Int(last), (1...20).contains(n) { return n }
        return numberWords[last]
    }

    static func display(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
