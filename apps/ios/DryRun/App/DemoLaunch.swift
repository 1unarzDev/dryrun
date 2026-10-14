import Foundation

/// Deterministic launch configuration for screenshots, UI review, and device previews.
/// Demo mode always uses the in-memory store and fictional sample households; it never reads or writes the vault.
///
///   -demoHousehold hh-oak|hh-lake|hh-pine   load a fictional household (enables demo mode)
///   -demoLocale en|es|vi                    plan/UI language
///   -demoTab next|rehearse|home|plan|help   initial tab (default: next, or rehearse with -demoScenario)
///   -demoScenario <scenarioID>              open that rehearsal
///   -demoStep start|decision|end            how far to advance it (end answers each decision with the recommended option)
///   -demoHomeMode 2d|3d|rooms               Home tab view
///   -demoPlan all|<id,id,...>               generate a plan for these scenarios at launch
///   -demoWritePlanPDFs                      DEBUG only: write EN/ES/VI PDFs + JSON to Documents/demo-plans, then DONE
///   -disableAnimations                      steadier screenshots
///   -uiTestingInMemory                      in-memory store without loading a household
struct DemoLaunch: Sendable, Equatable {
    enum Step: String, Sendable { case start, decision, end }

    var inMemory = false
    var householdID: String?
    var locale: String?
    var tab: String?
    var scenarioID: String?
    var step: Step = .start
    var homeMode: String?
    var planScenarios: [String] = []
    var writePlanPDFs = false
    var disableAnimations = false

    static let allScenarios = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood", "home-fire", "water-outage"]
    static let current = DemoLaunch(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            let v = arguments[i + 1]
            return v.hasPrefix("-") ? nil : v
        }
        inMemory = arguments.contains("-uiTestingInMemory")
        householdID = value("-demoHousehold")
        locale = value("-demoLocale").flatMap { ["en", "es", "vi"].contains($0) ? $0 : nil }
        tab = value("-demoTab")
        scenarioID = value("-demoScenario").flatMap { Self.allScenarios.contains($0) ? $0 : nil }
        step = value("-demoStep").flatMap(Step.init(rawValue:)) ?? .start
        homeMode = value("-demoHomeMode")
        if let p = value("-demoPlan") {
            planScenarios = p == "all" ? Self.allScenarios : p.split(separator: ",").map(String.init).filter(Self.allScenarios.contains)
        }
        writePlanPDFs = arguments.contains("-demoWritePlanPDFs")
        disableAnimations = arguments.contains("-disableAnimations")
    }

    /// Demo mode is active when a sample household is requested.
    var isActive: Bool { householdID != nil }
    var usesInMemoryStore: Bool { inMemory || isActive }
}
