import Foundation

/// Presentation and exercise setup, separate from facts, scored attempts and simulation authority.
/// Selecting an authored variant never confirms a preparation or edits the household.
public struct RehearsalSetupOption: Codable, Sendable, Equatable, Identifiable {
    public var id:String
    public var labelKey:String
    public var variantIDs:[String]
    public var focusServiceIDs:[String]
}
public struct RehearsalSetupQuestion: Codable, Sendable, Equatable, Identifiable {
    public var id:String
    public var promptKey:String
    public var explanationKey:String
    public var options:[RehearsalSetupOption]
    public var defaultOptionID:String {options[0].id}
}
public struct RehearsalExperienceDesign: Codable, Sendable, Equatable {
    public var scenarioID:String
    public var hazard:HazardKind
    public var symbol:String
    public var objectiveKey:String
    public var sceneKey:String
    public var debriefKey:String
    public var primaryServiceIDs:[String]
    public var questions:[RehearsalSetupQuestion]

    public static func design(for hazard:HazardKind,waterSource:WaterSourceKind?=nil)->Self {
        let id:String,symbol:String,services:[String]
        let specifications:[(String,[String])]
        switch hazard {
        case .homeFire:
            id="home-fire";symbol="flame";services=[Svc.handset,Svc.cellular]
            specifications=[("smoke",["recorded","hallway-smoke"]),("exit",["recorded","second-exit-blocked"])]
        case .tornado:
            id="tornado";symbol="tornado";services=[Svc.handset,Svc.cellular]
            specifications=[("timing",["recorded","night"]),("impact",["recorded","home-damaged"])]
        case .flashFlood:
            id="flash-flood";symbol="water.waves";services=[Svc.roads,Svc.transport]
            specifications=[("event",["recorded","householdLeak"]),("extent",["recorded","home-flooded"]),("focus",["access","supplies"])]
        case .freezePowerLoss:
            id="freeze-power-loss";symbol="snowflake";services=[Svc.heat,Svc.homePower]
            specifications=[("duration",["recorded","extended-outage"]),("focus",["warmth","power"])]
        case .heatGridStrain:
            id="heat-grid-strain";symbol="thermometer.sun";services=[Svc.cooling,Svc.homePower]
            specifications=[("grid",["recorded","no-rotating-outage"]),("focus",["cooling","water"])]
        case .waterOutage:
            id="water-outage";symbol="drop.triangle";services=[Svc.waterSupply,Svc.homePower]
            specifications=waterSource != nil && waterSource != .municipal ? [("focus",["water","power"]),("power",["recorded","with-power-loss"])]:[("advisory",["recorded","do-not-drink","do-not-use"]),("power",["recorded","with-power-loss"])]
        }
        let questions=specifications.map {topic,options in
            RehearsalSetupQuestion(id:"\(id).\(topic)",promptKey:"experience.\(id).setup.\(topic)",explanationKey:"experience.\(id).setup.\(topic).why",options:options.map {option in
                let focus:[String]=topic=="focus" ? (option=="power" ? [Svc.homePower]:option=="water" || option=="supplies" ? [Svc.waterSupply]:option=="access" ? [Svc.roads,Svc.transport]:[option=="warmth" ? Svc.heat:Svc.cooling]):[]
                return RehearsalSetupOption(id:option,labelKey:"experience.\(id).setup.\(topic).\(option)",variantIDs:topic=="focus" || option=="recorded" ? []:option=="no-rotating-outage" ? [option,"cooling-followup"]:[option],focusServiceIDs:focus)
            })
        }
        return .init(scenarioID:id,hazard:hazard,symbol:symbol,objectiveKey:"experience.\(id).objective",sceneKey:"experience.\(id).scene",debriefKey:"experience.\(id).debrief",primaryServiceIDs:services,questions:questions)
    }
    public static func design(scenarioID:String,household:HouseholdProfile?=nil)->Self? {
        HazardKind.allCases.map{design(for:$0,waterSource:household?.housing.waterSource)}.first{$0.scenarioID==scenarioID}
    }
    /// Unknown options fail rather than selecting a silent default. A local leak cannot also
    /// inherit the regional indoor-flood extent. Only variants actually in this pack can run.
    public func variants(answers:[String:String],scenario:ScenarioDefinition)throws->[String] {
        guard scenario.id==scenarioID,scenario.hazard==hazard,Set(answers.keys).isSubset(of:Set(questions.map(\.id))) else {throw SessionError.invalidCommand}
        var result:[String]=[]
        for question in questions {
            guard let selected=question.options.first(where:{$0.id==(answers[question.id] ?? question.defaultOptionID)}) else {throw SessionError.invalidCommand}
            result += selected.variantIDs
        }
        if result.contains("householdLeak") {result.removeAll{$0=="home-flooded"}}
        guard Set(result).isSubset(of:Set(scenario.variants.map(\.id))) else {throw SessionError.invalidCommand}
        return Array(Set(result)).sorted()
    }
    public func focusedServiceIDs(answers:[String:String])->[String] {
        let selected=questions.flatMap {q in q.options.first{$0.id==(answers[q.id] ?? q.defaultOptionID)}?.focusServiceIDs ?? []}
        return selected + primaryServiceIDs.filter{!selected.contains($0)}
    }
}

/// A resource drawing must retain unknown/empty and actual units. Only comparable, recorded
/// baseline/current values create a fill fraction; it is never a forecast or preparedness score.
public struct RehearsalResourceVisual:Codable,Sendable,Equatable,Identifiable {
    public var id:String
    public var current:ResourceQuantity
    public var baseline:ResourceQuantity?
    public var remainingFraction:Double? {
        guard let amount=current.amount,let initial=baseline,initial.unit==current.unit,let capacity=initial.amount,capacity.isFinite,capacity>0,amount.isFinite,amount>=0 else {return nil}
        return min(1,max(0,amount/capacity))
    }
    public var change:Double? {
        guard let amount=current.amount,let baseline,baseline.unit==current.unit,let initial=baseline.amount,initial.isFinite,amount.isFinite else {return nil}
        return amount-initial
    }
}

/// Same projection seam for the current authored cursor and the incremental receipt.
/// It never copies future authored states into the visible scene.
public struct RehearsalScenePresentation:Codable,Sendable,Equatable {
    public var design:RehearsalExperienceDesign
    public var simMinute:Int
    public var services:[String:ServiceState]
    public var resources:[RehearsalResourceVisual]
    public var advisory:WaterAdvisory?
    public var temperature:EducationalTemperature?
    public var roomTemperatures:[String:EducationalTemperature]?
    public var outsidePersonIDs:[String]?
    public var accountedPersonIDs:[String]?
    public var shelteredPersonIDs:[String]?
    public var relocated:Bool?
    public init(hazard:HazardKind,snapshot:SimulationSnapshot,baseline:SimulationSnapshot?,experience:HazardExperience?=nil,visibleEvents:[SimulationEvent]=[],snapshotHistory:[SimulationSnapshot]=[])throws {
        if let experience,experience.hazard != hazard {throw SessionError.invalidCommand}
        design = .design(for:hazard);simMinute=snapshot.simMinute;services=snapshot.services
        resources=snapshot.resources.keys.sorted().map{RehearsalResourceVisual(id:$0,current:snapshot.resources[$0]!,baseline:baseline?.resources[$0])}
        // Only already-visible, already-applied advisory events can supply authored advisory state.
        let appliedIDs=Set(snapshot.firedEventIDs + snapshotHistory.filter { prior in
            prior.simMinute < snapshot.simMinute || (prior.simMinute == snapshot.simMinute && prior.revealedEventCount != nil && snapshot.revealedEventCount != nil && prior.revealedEventCount! <= snapshot.revealedEventCount!)
        }.flatMap(\.firedEventIDs))
        advisory=experience?.waterAdvisory ?? visibleEvents.last(where:{$0.simMinute<=snapshot.simMinute && appliedIDs.contains($0.id) && $0.templateValues["advisory"] != nil}).flatMap{$0.templateValues["advisory"].flatMap(WaterAdvisory.init(rawValue:))}
        if hazard != .waterOutage {advisory=nil}
        temperature=experience?.temperature;roomTemperatures=experience?.roomTemperatures
        outsidePersonIDs=experience?.outsidePersonIDs;accountedPersonIDs=experience?.accountedPersonIDs;shelteredPersonIDs=experience?.shelteredPersonIDs;relocated=experience?.relocated
    }
}
