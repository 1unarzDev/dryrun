import Foundation

/// Inputs and acceptance rules for the optional "For your family" briefing on Prepare.
///
/// The ranker decides which preparations matter and in what order; that never changes. An on-device language model
/// may only restate the top few in terms of this household's situation. Everything it sees is built here: abstract
/// household facts (no names, notes, addresses, phone numbers or custom labels) and the already-localized step text
/// with names redacted. Everything it writes must pass `accept` or the authored text is shown instead.
public enum PlanBriefing {
    public static let maxSteps = 3
    public static let maxSentenceLength = 240

    /// Plain English facts about the household for the model's context. Enum-derived only.
    public static func familyFacts(_ h: HouseholdProfile, regionName: String? = nil) -> [String] {
        var facts = ["\(h.people.count) \(h.people.count == 1 ? "person" : "people") live in the home"]
        let ages = Dictionary(grouping: h.people.map(\.ageBand).filter { $0 != .unknown }, by: { $0 })
        for band in AgeBand.allCases where ages[band] != nil {
            facts.append("\(words(band.rawValue)): \(ages[band]!.count)")
        }
        let needs = h.people.flatMap(\.needs)
        for need in AssistanceNeed.allCases where needs.contains(need) {
            facts.append("a household member: \(words(need.rawValue))")
        }
        for purpose in EquipmentPurpose.allCases where h.equipment.contains(where: { $0.purpose == purpose }) {
            let e = h.equipment.first { $0.purpose == purpose }!
            var fact = "uses \(purpose == .other ? "essential equipment" : words(purpose.rawValue))"
            if e.requiresElectricalPower { fact += " that needs electricity" }
            if e.requiresColdStorage { fact += " that needs to stay cold" }
            facts.append(fact)
        }
        if !h.backupPower.isEmpty { facts.append("has backup power recorded") }
        if !h.pets.isEmpty { facts.append("pets: " + h.pets.map { words($0.kind.rawValue) }.joined(separator: ", ")) }
        if h.housing.homeType != .other { facts.append("home: \(words(h.housing.homeType.rawValue))") }
        if h.housing.tenancy != .other { facts.append("\(words(h.housing.tenancy.rawValue))") }
        if h.housing.heatingFuel != .unknown { facts.append("heating: \(words(h.housing.heatingFuel.rawValue))") }
        if h.housing.cooling != .unknown { facts.append("cooling: \(words(h.housing.cooling.rawValue))") }
        if h.housing.waterSource == .privateWell { facts.append("water from a private well") }
        facts.append(h.transport.hasVehicle ? "has a vehicle" : "no vehicle recorded")
        if let regionName { facts.append("lives in \(regionName), Texas") }
        return facts
    }

    /// Replaces people's names and custom equipment labels with role words, so step text can be shared with the
    /// model without names. Longest names first, whole words only, case-insensitive.
    public static func redact(_ text: String, household h: HouseholdProfile) -> String {
        var replacements: [(String, String)] = h.people.compactMap { p in
            let name = p.alias.trimmingCharacters(in: .whitespaces)
            guard name.count >= 2 else { return nil }
            return (name, p.isSelf == true ? "you" : p.relationship.map { "your \(words($0.rawValue))" } ?? "a household member")
        }
        replacements += h.equipment.compactMap { e in
            let label = e.label.trimmingCharacters(in: .whitespaces)
            guard label.count >= 2 else { return nil }
            return (label, words(e.purpose.rawValue))
        }
        replacements += h.contacts.compactMap { c in
            let name = c.alias.trimmingCharacters(in: .whitespaces)
            return name.count >= 2 ? (name, "your contact") : nil
        }
        var out = text
        for (name, role) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
            out = out.replacingOccurrences(of: "(?<![\\p{L}])\(NSRegularExpression.escapedPattern(for: name))(?![\\p{L}])",
                                           with: role, options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    /// Words a briefing must not introduce: clinical directions, survival or certainty claims, probabilities.
    /// A trailing `*` matches any ending, so conjugations are caught ("sobreviv*" covers "sobrevivirá").
    static let blocked: [String: [String]] = [
        "en": ["dose*", "dosage*", "mg", "surviv*", "die", "dies", "dying", "death*", "fatal*", "deadly", "guarant*", "safe", "safely", "safer",
               "probab*", "percent*", "chance*", "likely", "evacuate now", "boil*", "stop taking", "minute*", "hour*", "day*", "deadline*"],
        "es": ["dosis", "mg", "sobreviv*", "superviv*", "morir*", "muer*", "mortal*", "garantiz*", "seguro", "segura", "seguros", "seguras", "probab*",
               "por ciento", "posibilidad*", "evacúe ya", "hervir*", "hierv*", "deje de tomar", "minuto*", "hora*", "día*", "plazo*"],
    ]

    public static func supportsLocale(_ locale: String) -> Bool { blocked[locale] != nil }

    /// Accepts one generated sentence only when it adds no number, link, phone number or blocked word that the
    /// source text did not already contain, and stays short.
    public static func accept(_ candidate: String, sources: [String], locale: String) -> Bool {
        guard let terms = blocked[locale] else { return false }
        let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxSentenceLength else { return false }
        let source = sources.joined(separator: " ").lowercased()
        let lower = text.lowercased()
        if lower.contains("http") || lower.contains("www.") || lower.contains("@") { return false }
        let sentenceEnds = text.filter { ".!?".contains($0) }.count
        if sentenceEnds > 2 { return false }
        let sourceNumbers = Set(numbers(in: source))
        if numbers(in: lower).contains(where: { !sourceNumbers.contains($0) }) { return false }
        if lower.contains("%") && !source.contains("%") { return false }
        for term in terms where containsWord(term, in: lower) && !containsWord(term, in: source) { return false }
        return true
    }

    static func numbers(in s: String) -> [String] {
        var out: [String] = []; var current = ""
        for c in s { if c.isNumber { current.append(c) } else if !current.isEmpty { out.append(current); current = "" } }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func containsWord(_ term: String, in text: String) -> Bool {
        let stem = term.hasSuffix("*")
        let body = NSRegularExpression.escapedPattern(for: stem ? String(term.dropLast()) : term)
        let pattern = "(?<![\\p{L}])\(body)" + (stem ? "\\p{L}*" : "(?![\\p{L}])")
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func words(_ raw: String) -> String {
        let overrides = ["cpapOrBipap": "CPAP or BiPAP machine", "centralAC": "central AC", "windowOrPortableAC": "window or portable AC",
                         "spousePartner": "spouse or partner", "olderAdult": "older adult", "singleFamily": "single-family house",
                         "naturalGas": "natural gas", "deafOrHardOfHearing": "deaf or hard of hearing", "blindOrLowVision": "blind or low vision",
                         "cognitiveOrMemory": "memory or thinking support needs", "renter": "rents the home", "owner": "owns the home"]
        if let o = overrides[raw] { return o }
        return raw.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).lowercased()
    }
}
