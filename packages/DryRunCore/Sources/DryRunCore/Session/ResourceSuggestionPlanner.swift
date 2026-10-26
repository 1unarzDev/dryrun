import Foundation

/// Offline, reviewed mapping from the household's open preparation tasks (and confirmed supply gaps) to at most three
/// nearby-resource search plans. Same `ResourceSearchPlan` shape as the Gemini resources role, so the app renders both
/// the same way; text fields hold localization keys here. Plans never claim stock, activation, opening hours,
/// compatibility or safety: those stay listed as unknowns to check. Driving is never planned for a household without a car.
public enum ResourceSuggestionPlanner {
    public static let version = "dryrun.resource-plan-local/1"
    /// Categories whose places must come from independently reviewed official records, never from map listings.
    public static let officialOnly: Set<String> = ["emergencyManagement", "warmingCooling", "shelter"]

    struct Rule { let category: String; let purpose: String; let unknowns: [String]; let evidence: [String] }

    /// Preparation action (without the "prep." prefix) → resource rule. Tasks without a rule get no map search.
    static func rule(action: String, limitedBudget: Bool) -> Rule? {
        switch action {
        case "water":
            return Rule(category: "grocery", purpose: "resource.purpose.water",
                        unknowns: ["resource.unknown.stock", "resource.unknown.outageOperation"], evidence: ["resource.evidence.callAhead"])
        case "food":
            return Rule(category: limitedBudget ? "foodAssistance" : "grocery", purpose: "resource.purpose.food",
                        unknowns: ["resource.unknown.stock", limitedBudget ? "resource.unknown.eligibility" : "resource.unknown.outageOperation"],
                        evidence: ["resource.evidence.callAhead"])
        case "flashlight", "batteries":
            return Rule(category: "hardware", purpose: "resource.purpose.light", unknowns: ["resource.unknown.stock"], evidence: ["resource.evidence.callAhead"])
        case "smokeAlarms", "coAlarms":
            return Rule(category: "hardware", purpose: "resource.purpose.alarms", unknowns: ["resource.unknown.stock"], evidence: ["resource.evidence.callAhead"])
        case "firstAid", "medication":
            return Rule(category: "pharmacy", purpose: action == "medication" ? "resource.purpose.medication" : "resource.purpose.firstAid",
                        unknowns: ["resource.unknown.stock", "resource.unknown.hours"], evidence: ["resource.evidence.callAhead"])
        case "medicalBackup", "coldStorage", "equipmentSupplies":
            return Rule(category: "equipmentSupplier", purpose: "resource.purpose.equipment",
                        unknowns: ["resource.unknown.compatibility", "resource.unknown.stock"], evidence: ["resource.evidence.manufacturer"])
        case "heatCold":
            return Rule(category: "warmingCooling", purpose: "resource.purpose.heatCold",
                        unknowns: ["resource.unknown.activation", "resource.unknown.access"], evidence: ["resource.evidence.official"])
        case "shelterPlan", "floodPlan":
            return Rule(category: "emergencyManagement", purpose: "resource.purpose.officialPlanning",
                        unknowns: ["resource.unknown.activation"], evidence: ["resource.evidence.official"])
        default:
            return nil
        }
    }

    /// Travel the plan assumes: no driving without a car; a short radius on foot or by transit.
    public static func travel(transport: String) -> (mode: String, km: Double) {
        switch transport {
        case "car", "driving": ("driving", 15)
        case "noCar", "walking": ("walking", 3)
        case "transit": ("transit", 8)
        case "assistance": ("assistance", 8)
        default: ("walking", 3)
        }
    }

    /// At most `limit` plans, one per category, in task order with confirmed shortfalls first.
    public static func plans(tasks: [PreparationTaskProposal], gaps: [SupplyGap], transport: String, limitedBudget: Bool,
                             limit: Int = 3) -> [ResourceSearchPlan] {
        let short = Set(gaps.filter { ($0.deficit ?? 0) > 0 }.map(\.category))
        let ordered = tasks.enumerated().sorted { a, b in
            let aShort = short.contains(a.element.criterionID), bShort = short.contains(b.element.criterionID)
            return aShort != bShort ? aShort : (a.element.priority, a.offset) < (b.element.priority, b.offset)
        }.map(\.element)
        let (mode, km) = travel(transport: transport)
        var seen = Set<String>(), out: [ResourceSearchPlan] = []
        for task in ordered where out.count < limit {
            let action = task.actionID.hasPrefix("prep.") ? String(task.actionID.dropFirst(5)) : task.actionID
            guard let rule = rule(action: action, limitedBudget: limitedBudget), seen.insert(rule.category).inserted else { continue }
            let hazards = ["smokeAlarms": ["home-fire"], "shelterPlan": ["tornado"], "floodPlan": ["flash-flood"],
                           "heatCold": ["freeze-power-loss", "heat-grid-strain"]][action] ?? []
            out.append(ResourceSearchPlan(id: "local-\(rule.category)-\(task.id)", taskID: task.id, dependencyIDs: task.dependencyIDs, hazardIDs: hazards,
                                          category: rule.category, purpose: rule.purpose, unknowns: rule.unknowns, travelMode: mode,
                                          maximumDistanceKm: km, expansionLimit: 1, requiredEvidence: rule.evidence))
        }
        return out
    }

    /// Natural-language MapKit query for a map-searchable category (English: MapKit matches categories, not prose).
    public static func mapQuery(category: String) -> String? {
        guard !officialOnly.contains(category) else { return nil }
        return ["grocery": "grocery store", "foodAssistance": "food bank", "pharmacy": "pharmacy",
                "equipmentSupplier": "medical supply store", "hardware": "hardware store", "hospital": "hospital",
                "clothing": "clothing store", "policeStation": "police station", "fireStation": "fire station"][category]
    }

    /// The official directory service type that can satisfy an official-only category.
    public static func officialServiceTypes(category: String) -> [ResourceServiceType] {
        switch category {
        case "warmingCooling": [.warmingCenter, .coolingCenter]
        case "shelter": [.shelter]
        case "emergencyManagement": [.emergencyManagement]
        default: []
        }
    }
}
