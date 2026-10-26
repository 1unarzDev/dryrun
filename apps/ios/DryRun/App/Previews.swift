#if DEBUG
import SwiftUI
import DryRunCore

// Xcode canvas previews over the deterministic, offline AppModel.preview(...). Fictional data only.
// Change `locale:` to "es" / "vi" to check text expansion and draft labels.

#Preview("Onboarding") {
    OnboardingView().environment(AppModel(store: InMemoryPrivateDataStore()))
}

#Preview("Rehearse list") {
    NavigationStack { RehearseTabView() }.environment(AppModel.preview())
}

#Preview("Freeze — mid") {
    NavigationStack { RehearsalView(scenarioID: "freeze-power-loss") }
        .environment(AppModel.preview(scenarioID: "freeze-power-loss", step: .decision))
}

#Preview("Fire — end with routes") {
    NavigationStack { RehearsalView(scenarioID: "home-fire") }
        .environment(AppModel.preview(scenarioID: "home-fire", step: .end))
}

#Preview("Debrief — freeze") {
    NavigationStack { DebriefView() }
        .environment(AppModel.preview(scenarioID: "freeze-power-loss", step: .end))
}

#Preview("Home") {
    NavigationStack { HomeTabView() }.environment(AppModel.preview())
}

#Preview("Plan tab — VI") {
    NavigationStack { PlanTabView() }
        .environment(AppModel.preview(householdID: "hh-lake", locale: "vi", planScenarios: ["home-fire", "heat-grid-strain"]))
}

#Preview("Plan document — ES") {
    let model = AppModel.preview(householdID: "hh-pine", locale: "es", planScenarios: ["home-fire", "tornado"])
    return NavigationStack {
        if let plan = model.savedPlan { PlanDocumentView(doc: plan) } else { Text("No plan") }
    }
    .environment(model)
}

#Preview("Help") {
    NavigationStack { HelpTabView() }.environment(AppModel.preview())
}
#endif
