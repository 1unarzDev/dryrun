import SwiftUI
import DryRunCore

/// One launch page with a few explicit exercise assumptions, never household confirmation.
struct RehearsalSetupView: View {
    @Environment(AppModel.self) private var model
    let design: RehearsalExperienceDesign
    @Binding var answers: [String:String]
    @Binding var originID: String
    @Binding var waterEntryID: String
    @Binding var refugeID: String
    @Binding var startingSpaceIDs: [String:String]
    let onStart: () -> Void
    private var tint: Color { RehearseTabView.tints[design.scenarioID] ?? Theme.accent }

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: design.symbol).font(.largeTitle).foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(l(design.objectiveKey)).font(.title2.weight(.bold))
                    Text(l("experience.setup.caption")).font(.callout).foregroundStyle(.secondary)
                }
            }
            if let household = model.household {
                SectionCard(title: l("experience.setup.people"), systemImage: "person.2") {
                    Text(household.people.map { $0.localizedLabel(l) }.joined(separator: ", ")).font(.callout)
                    Text(model.home?.label ?? l("experience.setup.noHome")).font(.footnote).foregroundStyle(.secondary)
                    readinessContext(household)
                }
            }
            ForEach(design.questions) { question in
                // A local leak has its room extent chosen on the existing assumptions inspector.
                // The regional flooded-home condition must not appear to apply to it.
                if !(design.hazard == .flashFlood && question.id.hasSuffix(".extent") && answers["flash-flood.event"] == "householdLeak") {
                    questionCard(question)
                }
            }
            if let home = model.home, design.hazard == .homeFire || design.hazard == .flashFlood {
                SectionCard(title: l("experience.setup.rooms"), systemImage: "square.split.2x2") {
                    if design.hazard == .homeFire {
                        Picker(l("experience.setup.fireOrigin"), selection: $originID) {
                            Text(l("experience.setup.recorded")).tag("")
                            ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                        }.accessibilityIdentifier("rehearsal.setup.origin")
                    } else {
                        Picker(l("experience.setup.waterEntry"), selection: $waterEntryID) {
                            Text(l("experience.setup.extentUnknown")).tag("")
                            ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                        }.accessibilityIdentifier("rehearsal.setup.waterEntry")
                        if answers["flash-flood.event"] != "householdLeak" {
                            Picker(l("spatial.higher-refuge-to-review-optional"), selection: $refugeID) {
                                Text(l("spatial.no-refuge-established")).tag("")
                                ForEach(home.spaces.filter { $0.kind != .closet }) {
                                    Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id)
                                }
                            }.accessibilityIdentifier("rehearsal.setup.refuge")
                            Text(l("spatial.refuge-check-note")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(l("experience.setup.roomAssumption")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let home = model.home, let household = model.household,
               [.homeFire, .tornado, .flashFlood].contains(design.hazard) {
                DisclosureGroup(l("experience.setup.startingRooms")) {
                    Text(l("experience.setup.startingRooms.why")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(household.people) { person in
                        Picker(l("spatial.start-person", ["name": person.localizedLabel(l)]), selection: Binding(
                            get: { startingSpaceIDs[person.id] ?? "" },
                            set: { startingSpaceIDs[person.id] = $0 }
                        )) {
                            Text(l("spatial.use-recorded-assignment")).tag("")
                            ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                        }.accessibilityIdentifier("rehearsal.setup.start.\(person.id)")
                    }
                }.accessibilityIdentifier("rehearsal.setup.startingRooms")
            }
            Button(action: onStart) { Label(l("experience.setup.start"), systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle(tint: tint))
                .disabled(model.isWorking)
                .accessibilityIdentifier("rehearsal.setup.start")
        }
        .accessibilityIdentifier("rehearsal.setup")
    }
    @ViewBuilder private func readinessContext(_ household: HouseholdProfile) -> some View {
        let l = model.localizer
        let thermal = design.hazard == .freezePowerLoss || design.hazard == .heatGridStrain
        let relevantPeople = household.people.filter { !relevantNeeds($0).isEmpty }
        ForEach(Array(relevantPeople.prefix(2))) { person in
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("\(person.localizedLabel(l)): \(relevantNeeds(person).map { DisplayNames.name($0.rawValue, localizer: l) }.joined(separator: ", "))")
                    .font(.callout.weight(.semibold))
                Text(l("experience.context.assistance")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        if thermal, let equipment = household.equipment.first(where: { $0.isEssential && ($0.requiresElectricalPower || $0.requiresColdStorage) }) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(equipment.localizedLabel(l)).font(.callout.weight(.semibold))
                Text(l("experience.context.equipment")).font(.footnote).foregroundStyle(.secondary)
                if let instructions = equipment.storageInstructions, !instructions.isEmpty {
                    Text(instructions).font(.footnote)
                }
            }
        }
        if design.hazard == .waterOutage || design.hazard == .heatGridStrain || design.hazard == .freezePowerLoss {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(household.supplies.storedWaterGallons.confirmedValue.map {
                    "\(l("experience.scene.waterStock")): \(ServiceNames.quantity($0, unit: "gal", localizer: l))"
                } ?? l("experience.context.waterUnknown")).font(.callout.weight(.semibold))
                Text(l("experience.context.water")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func relevantNeeds(_ person: Person) -> [AssistanceNeed] {
        person.needs.filter { need in
            switch need {
            case .heatSensitive: return design.hazard == .heatGridStrain
            case .coldSensitive: return design.hazard == .freezePowerLoss
            default: return true
            }
        }
    }
    private func questionCard(_ question: RehearsalSetupQuestion) -> some View {
        let l = model.localizer
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(l(question.promptKey)).font(.headline)
            Text(l(question.explanationKey)).font(.footnote).foregroundStyle(.secondary)
            ForEach(question.options) { option in
                let selected = (answers[question.id] ?? question.defaultOptionID) == option.id
                Button { answers[question.id] = option.id } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(selected ? tint : Color.secondary)
                        Text(l(option.labelKey)).font(.callout.weight(selected ? .semibold : .regular)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.m).frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                    .background(selected ? tint.opacity(0.10) : Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(selected ? tint : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("rehearsal.setup.\(question.id).\(option.id)")
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// Six separate compositions. Every metric is a current host projection, never a wall-clock
/// animation, invented sensor value or display-only state transition.
struct HazardStatusScene: View {
    @Environment(AppModel.self) private var model
    let presentation: RehearsalScenePresentation
    let household: HouseholdProfile
    var home: HomeModel? = nil
    var focusedServiceIDs: [String] = []
    var isHouseholdLeak = false
    private var design: RehearsalExperienceDesign { presentation.design }
    private var tint: Color { RehearseTabView.tints[design.scenarioID] ?? Theme.accent }
    private var l: Localizer { model.localizer }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: design.symbol).font(.system(size: 32, weight: .semibold)).foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(l(design.sceneKey)).font(.title3.weight(.bold))
                    Text(l(design.objectiveKey)).font(.callout).foregroundStyle(.secondary)
                }
            }
            switch design.hazard {
            case .homeFire: fire
            case .tornado: tornado
            case .flashFlood: flood
            case .freezePowerLoss: freeze
            case .heatGridStrain: heat
            case .waterOutage: water
            }
            Text(l("experience.scene.notMeasured")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.13), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rehearsal.hazardScene.\(design.scenarioID)")
    }
    private var fire: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: "door.left.hand.open").font(.system(size: 48)).foregroundStyle(tint)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Image(systemName: "person.3.sequence").font(.system(size: 40)).foregroundStyle(.primary)
            }.frame(maxWidth: .infinity).padding(.vertical, Theme.Space.m).accessibilityHidden(true)
            if let outside = presentation.outsidePersonIDs, let accounted = presentation.accountedPersonIDs {
                roster(l("experience.scene.outside"), ids: outside)
                roster(l("experience.scene.accounted"), ids: accounted)
            } else { Text(l("experience.scene.notTracked")).font(.footnote).foregroundStyle(.secondary) }
            Text(l("experience.scene.noSafety")).font(.footnote)
        }
    }
    private var tornado: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: "window.vertical.closed").font(.system(size: 36)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Image(systemName: "house.lodge").font(.system(size: 52)).foregroundStyle(tint)
            }.frame(maxWidth: .infinity).padding(.vertical, Theme.Space.m).accessibilityHidden(true)
            if let sheltered = presentation.shelteredPersonIDs { roster(l("experience.scene.sheltered"), ids: sheltered) }
            else { Text(l("experience.scene.notTracked")).font(.footnote).foregroundStyle(.secondary) }
            service(Svc.alerts, key: "experience.scene.alerts", symbol: "antenna.radiowaves.left.and.right")
            Text(l("experience.scene.noSafety")).font(.footnote)
        }
    }
    private var flood: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: isHouseholdLeak ? "drop" : "water.waves").font(.system(size: 40)).foregroundStyle(tint)
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                Image(systemName: isHouseholdLeak ? "bolt.slash" : "car.side").font(.system(size: 44)).foregroundStyle(.primary)
            }.frame(maxWidth: .infinity).padding(.vertical, Theme.Space.m).accessibilityHidden(true)
            if isHouseholdLeak {
                Text(l("experience.scene.leak")).font(.callout)
            } else {
                service(Svc.roads, key: "experience.scene.roads", symbol: "road.lanes")
                service(Svc.transport, key: "experience.scene.transport", symbol: "car.side")
            }
            if focusedServiceIDs.first == Svc.waterSupply {
                service(Svc.waterSupply, key: "experience.scene.water", symbol: "drop")
            }
            Text(l(isHouseholdLeak ? "experience.scene.leakReview" : design.debriefKey)).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var freeze: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                Image(systemName: "house.and.flag").font(.system(size: 52)).foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(thermalServices, id: \.self) { id in
                        service(id, key: id == Svc.heat ? "experience.scene.heat" : "experience.scene.power", symbol: id == Svc.heat ? "heater.vertical" : "bolt")
                    }
                }
            }
            temperature
            reserves
        }
    }
    private var heat: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                Image(systemName: "sun.max").font(.system(size: 56)).foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(thermalServices, id: \.self) { id in
                        service(id, key: id == Svc.waterSupply ? "experience.scene.water" : id == Svc.homePower ? "experience.scene.power" : "experience.scene.cooling", symbol: id == Svc.waterSupply ? "drop" : id == Svc.homePower ? "bolt" : "air.conditioner.horizontal")
                    }
                }
            }
            temperature
            if let rooms = presentation.roomTemperatures, let home {
                ForEach(rooms.keys.sorted(), id: \.self) { id in
                    if let range = rooms[id] {
                        HStack(alignment: .firstTextBaseline) {
                            Text(HomeScenePresentation.roomLabel(id, in: home)).font(.callout)
                            Spacer(minLength: Theme.Space.s)
                            Text(rangeLabel(range)).font(.callout.monospacedDigit())
                        }
                    }
                }
            }
        }
    }
    private var thermalServices: [String] {
        let defaults = [design.hazard == .freezePowerLoss ? Svc.heat : Svc.cooling, Svc.homePower]
        return Array((focusedServiceIDs + defaults).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(3))
    }
    private var water: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                Image(systemName: "spigot").font(.system(size: 48)).foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    service(Svc.waterSupply, key: "experience.scene.water", symbol: "drop")
                    Text(l(presentation.advisory.map { "experience.scene.\($0.rawValue)" } ?? "experience.scene.noAdvisory"))
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                }
            }
            if focusedServiceIDs.first == Svc.homePower || presentation.services[Svc.homePower] == .unavailable {
                service(Svc.homePower, key: "experience.scene.power", symbol: "bolt")
            }
            if let stock = presentation.resources.first(where: { $0.id == "res.water.stored" }) { resource(stock, tank: true) }
            else { Text(l("experience.scene.unknown")).font(.callout).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) { activities }
                VStack(alignment: .leading, spacing: Theme.Space.s) { activities }
            }
            Text(l("experience.scene.followAdvisory")).font(.footnote)
            Text(l("experience.scene.waterCaveat")).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var activities: some View {
        Label(l("experience.scene.drink"), systemImage: "cup.and.saucer")
        Label(l("experience.scene.cook"), systemImage: "fork.knife")
        Label(l("experience.scene.hygiene"), systemImage: "hands.sparkles")
    }
    private var temperature: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(l("experience.scene.temperature")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let range = presentation.temperature { Text(rangeLabel(range)).font(.title2.weight(.bold).monospacedDigit()) }
            else { Text(l("experience.scene.temperatureUnknown")).font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private func rangeLabel(_ range: EducationalTemperature) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)).locale(Locale(identifier: l.locale))
        return "\(range.lowerC.formatted(format))–\(range.upperC.formatted(format)) °C"
    }
    private var reserves: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(l("experience.scene.energy")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            let stock = presentation.resources.filter { $0.id.hasPrefix("res.backup.") || $0.id.hasPrefix("res.device.") || $0.id == "res.handset.hours" }
            if stock.isEmpty { Text(l("experience.scene.noLedger")).font(.footnote).foregroundStyle(.secondary) }
            ForEach(stock) { item in resource(item) }
        }
    }
    private func resource(_ item: RehearsalResourceVisual, tank: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Label(ServiceNames.name(item.id, household: household, localizer: l), systemImage: tank ? "waterbottle" : "battery.75percent")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: Theme.Space.s)
                Text(item.current.amount.map { ServiceNames.quantity($0, unit: item.current.unit, localizer: l) } ?? l("experience.scene.unknown"))
                    .font(.callout.monospacedDigit())
            }
            if let fraction = item.remainingFraction {
                if tank {
                    HStack(alignment: .center, spacing: Theme.Space.l) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceMuted)
                            Rectangle().fill(tint.opacity(0.7)).frame(height: 104 * CGFloat(fraction))
                        }
                        .frame(width: 72, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint, lineWidth: 2))
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(l("experience.scene.remaining")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(ServiceNames.quantity(item.current.amount ?? 0, unit: item.current.unit, localizer: l))
                                .font(.title2.weight(.bold).monospacedDigit())
                            Text(l("experience.scene.baselineScale")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceMuted)
                            Capsule().fill(tint).frame(width: geometry.size.width * CGFloat(fraction))
                        }
                    }.frame(height: 8).accessibilityHidden(true)
                }
            }
            if let change = item.change, change != 0 {
                Text(l(change < 0 ? "experience.scene.usedSinceStart" : "experience.scene.addedSinceStart", [
                    "quantity": ServiceNames.quantity(abs(change), unit: item.current.unit, localizer: l)
                ])).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            if let baseline = item.baseline, let amount = baseline.amount {
                Text("\(l("experience.scene.baseline")): \(ServiceNames.quantity(amount, unit: baseline.unit, localizer: l))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private func service(_ id: String, key: String, symbol: String) -> some View {
        let state = presentation.services[id] ?? .unknown
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Label(l(key), systemImage: symbol).font(.callout)
            Spacer(minLength: Theme.Space.s)
            Label(l("common.status.\(state.rawValue)"), systemImage: Theme.symbol(for: state))
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.color(for: state))
        }.accessibilityElement(children: .combine)
    }
    private func roster(_ title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(title): \(ids.count)/\(household.people.count)").font(.callout.weight(.semibold).monospacedDigit())
            if !ids.isEmpty { Text(household.people.filter { ids.contains($0.id) }.map { $0.localizedLabel(l) }.joined(separator: ", ")).font(.footnote) }
        }
    }
}

/// Specific completed-run readings. Does not infer arrivals from a feasible route.
struct RehearsalDebriefOutcomes: View {
    @Environment(AppModel.self) private var model
    let evidence: RehearsalDebriefEvidence
    let household: HouseholdProfile
    let home: HomeModel?

    var body: some View {
        let l = model.localizer
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(l("experience.debrief.outcomes")).font(.headline)
            if !evidence.routes.isEmpty {
                ForEach(evidence.routes, id: \.request.personID) { route in
                    let person = household.people.first { $0.id == route.request.personID }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(person?.localizedLabel(l) ?? l("experience.scene.unknown")).font(.callout.weight(.semibold))
                        if route.primary != nil {
                            Text(l("experience.debrief.routeAvailable")).font(.footnote)
                            if let home, let steps = HomeScenePresentation.routeSteps(route, in: home, localizer: l) {
                                Label(steps, systemImage: evidence.scene.design.hazard == .homeFire ? "figure.walk.departure" : "house")
                                    .font(.footnote.weight(.semibold))
                            }
                            if route.primary?.verificationNeeded.isEmpty == false {
                                Text(l("experience.scene.routeFactsUnknown")).font(.footnote).foregroundStyle(Theme.caution)
                            }
                            if evidence.scene.design.hazard == .homeFire {
                                Text(l(HomeScenePresentation.alternativeKey(route))).font(.footnote).foregroundStyle(.secondary)
                                if let home, route.isCurrent(for: home) {
                                    if let steps = HomeScenePresentation.routeSteps(route, in: home, localizer: l, alternative: true) {
                                        Text(l("experience.route.alternative", ["steps": steps])).font(.footnote)
                                    }
                                    if !route.sharedChokepoints.isEmpty {
                                        Text(l("experience.route.shared", ["connections": route.sharedChokepoints.map {
                                            HomeScenePresentation.routeElementLabel($0, in: home, localizer: l)
                                        }.joined(separator: "; ")])).font(.footnote).foregroundStyle(Theme.caution)
                                    }
                                }
                            }
                        } else {
                            Text(l("experience.debrief.noRoute", [
                                "reason": l("plan.route.reason.\((route.noRouteReason ?? .incompleteConnectivity).rawValue)")]))
                                .font(.footnote).foregroundStyle(Theme.critical)
                        }
                    }
                }
                Text(l("experience.debrief.routesNotArrivals")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(evidence.serviceIDs, id: \.self) { id in
                let state = evidence.scene.services[id] ?? .unknown
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(ServiceNames.name(id, household: household, localizer: l)).font(.callout)
                    Spacer(minLength: Theme.Space.s)
                    StatusPill(text: l("common.status.\(state.rawValue)"), systemImage: Theme.symbol(for: state), tint: Theme.color(for: state))
                }.accessibilityElement(children: .combine)
            }
            if let relocation = evidence.relocation {
                Text(l("experience.debrief.relocation.\(relocation.rawValue)")).font(.callout)
            }
            if let advisory = evidence.scene.advisory {
                Text(l("experience.scene.\(advisory.rawValue)")).font(.callout.weight(.semibold))
                Text(l("experience.scene.followAdvisory")).font(.footnote)
            }
            ForEach(evidence.resourceReadings) { item in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(ServiceNames.name(item.id, household: household, localizer: l)).font(.callout.weight(.semibold))
                    Text(item.current.amount.map { ServiceNames.quantity($0, unit: item.current.unit, localizer: l) } ?? l("experience.scene.unknown"))
                        .font(.callout.monospacedDigit())
                    if let change = item.change, change != 0 {
                        Text(l(change < 0 ? "experience.scene.usedSinceStart" : "experience.scene.addedSinceStart", [
                            "quantity": ServiceNames.quantity(abs(change), unit: item.current.unit, localizer: l)
                        ])).font(.footnote).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
            }
            Text(l("experience.debrief.unresolved", ["count": PlanFormatting.number(Double(evidence.unresolvedRequirementIDs.count), locale: l.locale)]))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("debrief.outcomes.\(evidence.scene.design.scenarioID)")
    }
}
