import Foundation

/// Versioned educational mechanics, never a forecast of injury, spread or safe exposure.
public struct HazardExperience: Codable, Sendable, Equatable {
    public static let version = "dryrun.hazard-mechanics/5"
    public static let supportedVersions = ["dryrun.hazard-mechanics/1","dryrun.hazard-mechanics/2","dryrun.hazard-mechanics/3","dryrun.hazard-mechanics/4",version]
    public var mechanicsVersion = version
    public var hazard: HazardKind
    public var scene: String
    public var objective: String
    public var supportedActions: [String]
    /// Host-validated examples at this receipt; user selection still requires an atomic preview.
    public var feasibleCommands: [SessionCommand]?
    public var outsidePersonIDs: [String]
    public var accountedPersonIDs: [String]
    public var shelteredPersonIDs: [String]
    public var destinationIDs:[String]
    public var occupantRoomIDs:[String:String]
    public var shelterRoomID:String?
    public var escapeHelperByPersonID:[String:String]?
    public var refugeRoomID:String?
    public var refugedPersonIDs:[String]?
    public var relocated: Bool
    public var temperature: EducationalTemperature?
    public var waterAdvisory: WaterAdvisory?
    public var waterService: ServiceState?
    public var availableWaterGallons: Double?
    public var selectedProtection: String?
    /// Version 2 heat: room-specific educational ranges and explicit chosen shading assumptions.
    public var roomTemperatures: [String:EducationalTemperature]?
    public var shadedRoomIDs: [String]?
    public var conditioningService: ServiceState?
    public var roomCoolingCoverageUnknown: Bool?
    public var openGapIDs:[String]
    public var identifiedGapIDs:[String]
    public var debrief: [HazardDebriefFact]
}
public struct EducationalTemperature: Codable, Sendable, Equatable {
    public var lowerC: Double
    public var upperC: Double
    public var model = "illustrative-room-range/1"
    public var assumption = "Synthetic exercise range, not measured temperature or medical tolerance. With lost conditioning, drift is 0.5–1.0 C/hour toward a cold 5–10 C or hot 35–40 C boundary; recorded warmth/shade halves drift."
}
public struct HazardDebriefFact: Codable, Sendable, Equatable {
    public var kind: String
    public var subjectIDs: [String]
    public var eventIDs: [String]
    public var nextActionID: String
}
struct HazardProgress {
    var outside = Set<String>()
    var accounted = Set<String>()
    var identifiedGaps=Set<String>()
    var escapeHelperByPersonID:[String:String]=[:]
    var supportsActionProgress:Bool {mechanicsVersion == "dryrun.hazard-mechanics/5"}
    var supportsEscapeAccompaniment:Bool {supportsActionProgress}
    var protection: String?
    var mechanicsVersion:String
    var roomTemperatures:[String:EducationalTemperature]=[:]
    var shadedRoomIDs=Set<String>()
    var roomCoverageUnknown:Bool
    var usesRoomHeat:Bool {mechanicsVersion != "dryrun.hazard-mechanics/1"}
    var supportsRecordedGapChecks:Bool {mechanicsVersion == "dryrun.hazard-mechanics/3" || supportsRefugeArrival}
    var supportsRefugeArrival:Bool {mechanicsVersion == "dryrun.hazard-mechanics/4" || supportsEscapeAccompaniment}
    var lowerC: Double
    var upperC: Double
    init(_ hazard: HazardKind,version:String,roomIDs:[String],roomCoverageUnknown:Bool) {
        self.roomCoverageUnknown=roomCoverageUnknown
        mechanicsVersion=version
        lowerC = hazard == .heatGridStrain ? 27 : 19
        upperC = hazard == .heatGridStrain ? 29 : 21
        if hazard == .heatGridStrain,usesRoomHeat {
            roomTemperatures=Dictionary(uniqueKeysWithValues:Set(roomIDs).map {($0,Self.roomRange(lowerC:27,upperC:29))})
        }
    }
    static func roomRange(lowerC:Double,upperC:Double)->EducationalTemperature {
        var range=EducationalTemperature(lowerC:lowerC,upperC:upperC)
        range.model="illustrative-room-range/2"
        range.assumption="Synthetic room exercise, not a measured temperature or medical tolerance. Lost cooling drifts 0.5–1.0 C/hour toward 35–40 C; reduced cooling halves drift. Unknown cooling permits zero lower-bound drift. Choosing shading halves drift only in that recorded room; multiple rooms do not stack whole-home credit."
        return range
    }
}
extension RunState {
    mutating func advanceHazardTemperature(minutes: Double) {
        guard var progress=hazardProgress, !relocated else {return}
        let hours=minutes/60
        let protection=progress.protection == nil ? 1.0 : 0.5
        if scenario.hazard == .freezePowerLoss, services[Svc.heat] != .operational {
            progress.lowerC=max(5,progress.lowerC-hours*protection)
            progress.upperC=max(10,progress.upperC-hours*0.5*protection)
        } else if scenario.hazard == .heatGridStrain,progress.usesRoomHeat,!progress.roomTemperatures.isEmpty {
            let suppliedCooling=services[Svc.cooling] ?? .unknown
            let cooling=progress.roomCoverageUnknown && (suppliedCooling == .operational || suppliedCooling == .degraded) ? ServiceState.unknown:suppliedCooling
            let factor=cooling == .operational ? 0.0:cooling == .degraded ? 0.5:1.0
            for roomID in progress.roomTemperatures.keys.sorted() {
                var range=progress.roomTemperatures[roomID]!
                let shade=progress.shadedRoomIDs.contains(roomID) ? 0.5:1.0
                let lowerDrift=cooling == .unknown ? 0:hours*0.5*factor*shade
                range.lowerC=min(35,range.lowerC+lowerDrift)
                range.upperC=min(40,range.upperC+hours*factor*shade)
                if progress.roomCoverageUnknown,!range.assumption.contains("Localized cooling") {range.assumption += " Localized cooling is recorded, but its room coverage is unrecorded; powered service does not establish cooling in this room."}
                progress.roomTemperatures[roomID]=range
            }
            progress.lowerC=progress.roomTemperatures.values.map(\.lowerC).min()!
            progress.upperC=progress.roomTemperatures.values.map(\.upperC).max()!
        } else if scenario.hazard == .heatGridStrain, services[Svc.cooling] != .operational {
            progress.lowerC=min(35,progress.lowerC+hours*0.5*protection)
            progress.upperC=min(40,progress.upperC+hours*protection)
        }
        hazardProgress=progress
    }
    /// Physical transitions require an explicit user command and use the existing route/allocator owners.
    mutating func applyHazardAction(_ command: SessionCommand) throws {
        guard var progress=hazardProgress else {throw SessionError.invalidCommand}
        switch command.kind {
        case "identifyGap":
            guard let id=command.target,openHazardGaps().contains(id),progress.identifiedGaps.insert(id).inserted else {throw SessionError.invalidCommand}
        case "escape":
            guard scenario.hazard == .homeFire, let personID=command.target,
                  !progress.outside.contains(personID),let person=household.people.first(where:{$0.id==personID}),let home,
                  let exitID=command.value else {throw SessionError.invalidCommand}
            if progress.supportsEscapeAccompaniment,person.needs.contains(.needsHelperToEvacuate),progress.escapeHelperByPersonID[personID]==nil {throw SessionError.invalidCommand}
            // Excluding other exterior exits asks the authoritative planner for precisely the chosen exit.
            let otherExits=home.portals.filter {portal in
                portal.id != exitID && (portal.sideA == .exterior || portal.sideB == .exterior)
            }.map(\.id)
            let route=planner.plan(RouteRequest(personID:personID,startSpaceID:startSpace(for:person),mobility:mobility(for:person),
                exclusions:ScenarioExclusions(blockedSpaceIDs:spatialState?.affectedSpaceIDs ?? [],blockedPortalIDs:Array(Set((spatialState?.affectedPortalIDs ?? [])+otherExits)).sorted())),in:home)
            guard route.primary?.exitPortalID == exitID else {throw SessionError.invalidCommand}
            currentRoutes[personID]=route
            progress.outside.insert(personID)
        case "accompanyEscape":
            guard progress.supportsEscapeAccompaniment,scenario.hazard == .homeFire,
                  let personID=command.target,let exitID=command.value,let home,
                  let person=household.people.first(where:{$0.id==personID}),
                  let helperID=person.helperPersonID,helperID != personID,
                  let helper=household.people.first(where:{$0.id==helperID}),
                  !helper.needs.contains(.needsHelperToEvacuate),
                  !progress.outside.contains(personID),!progress.outside.contains(helperID) else {throw SessionError.invalidCommand}
            let exclusions=ScenarioExclusions(blockedSpaceIDs:spatialState?.affectedSpaceIDs ?? [],blockedPortalIDs:spatialState?.affectedPortalIDs ?? [])
            let approach=planner.plan(RouteRequest(personID:helperID,startSpaceID:startSpace(for:helper),mobility:mobility(for:helper),exclusions:exclusions,purpose:.helperReach,destinationSpaceID:startSpace(for:person)),in:home)
            guard approach.primary != nil else {throw SessionError.invalidCommand}
            // An atomic candidate establishes the actual approach, then requires BOTH
            // people to traverse the selected exit using their own mobility constraints.
            // It models accompaniment, never a lift/carry technique or reentry rescue.
            var candidate=self
            let index=candidate.household.people.firstIndex(where:{$0.id==helperID})!
            var options=candidate.input.effectiveSpatialOptions;options.startingSpaceIDs[helperID]=startSpace(for:person);candidate.input.spatialOptions=options
            candidate.household.people[index].sleepingSpaceID=startSpace(for:person)
            candidate.hazardProgress?.escapeHelperByPersonID[personID]=helperID
            try candidate.applyHazardAction(.init(kind:"escape",target:personID,value:exitID))
            try candidate.applyHazardAction(.init(kind:"escape",target:helperID,value:exitID))
            self=candidate;return
        case "accountOutside":
            guard scenario.hazard == .homeFire,let person=command.target,progress.outside.contains(person),
                  home?.meetingPoint?.verification == .verified else {throw SessionError.invalidCommand}
            if progress.supportsRecordedGapChecks,progress.accounted.contains(person) {throw SessionError.invalidCommand}
            progress.accounted.insert(person)
        case "accompanyShelter":
            guard scenario.hazard == .tornado,let personID=command.target,let helperID=command.value,
                  personID != helperID,let home,let shelter=shelterSpace,
                  let person=household.people.first(where:{$0.id==personID}),
                  person.helperPersonID==helperID,
                  let helper=household.people.first(where:{$0.id==helperID}),
                  household.housing.homeType != .manufacturedHome else {throw SessionError.invalidCommand}
            if progress.supportsActionProgress,startSpace(for:person)==shelter.id {throw SessionError.invalidCommand}
            let approach=planner.plan(RouteRequest(personID:helperID,startSpaceID:startSpace(for:helper),mobility:mobility(for:helper),
                exclusions:.none,purpose:.helperReach,destinationSpaceID:startSpace(for:person)),in:home)
            guard approach.primary != nil else {throw SessionError.invalidCommand}
            // This records sequential accompaniment through supported paths, not a lift/carry technique.
            // Both people must be able to traverse the route using their recorded mobility constraints.
            var candidate=self
            let helperIndex=candidate.household.people.firstIndex(where:{$0.id==helperID})!
            var options=candidate.input.effectiveSpatialOptions;options.startingSpaceIDs[helperID]=startSpace(for:person);candidate.input.spatialOptions=options
            candidate.household.people[helperIndex].sleepingSpaceID=startSpace(for:person)
            try candidate.applyHazardAction(.init(kind:"reachShelter",target:personID,value:shelter.id))
            try candidate.applyHazardAction(.init(kind:"reachShelter",target:helperID,value:shelter.id))
            self=candidate;return
        case "reachHigherRefuge":
            guard progress.supportsRefugeArrival,scenario.hazard == .flashFlood,!relocated,
                  let personID=command.target,let destination=command.value,
                  let index=household.people.firstIndex(where:{$0.id==personID}),let home,
                  let objective=currentRoutes[personID]?.request,objective.purpose == .higherRefuge,
                  objective.destinationSpaceID == destination,currentRoutes[personID]?.primary != nil,
                  startSpace(for:household.people[index]) != destination else {throw SessionError.invalidCommand}
            // The warning/stage owner established the refuge from explicit affected-floor
            // relationships. Recompute the exact approach; arbitrary upstairs rooms or
            // a tornado closet are never promoted to flood refuge by this action.
            let route=planner.plan(RouteRequest(personID:personID,startSpaceID:startSpace(for:household.people[index]),mobility:mobility(for:household.people[index]),exclusions:objective.exclusions,purpose:.higherRefuge,destinationSpaceID:destination),in:home)
            guard route.primary != nil else {throw SessionError.invalidCommand}
            var options=input.effectiveSpatialOptions;options.startingSpaceIDs[personID]=destination;input.spatialOptions=options
            household.people[index].sleepingSpaceID=destination
            currentRoutes[personID]=planner.plan(RouteRequest(personID:personID,startSpaceID:destination,mobility:mobility(for:household.people[index]),exclusions:objective.exclusions,purpose:.higherRefuge,destinationSpaceID:destination),in:home)
        case "reachShelter":
            guard scenario.hazard == .tornado,household.housing.homeType != .manufacturedHome,
                  let shelter=shelterSpace,command.value==shelter.id,let personID=command.target,
                  let index=household.people.firstIndex(where:{$0.id==personID}),let home else {throw SessionError.invalidCommand}
            let person=household.people[index]
            if progress.supportsActionProgress,startSpace(for:person)==shelter.id {throw SessionError.invalidCommand}
            let route=planner.plan(RouteRequest(personID:personID,startSpaceID:startSpace(for:person),mobility:mobility(for:person),
                exclusions:.none,purpose:.interiorShelter,destinationSpaceID:shelter.id),in:home)
            guard route.primary != nil else {throw SessionError.invalidCommand}
            var options=input.effectiveSpatialOptions;options.startingSpaceIDs[personID]=shelter.id;input.spatialOptions=options
            household.people[index].sleepingSpaceID=shelter.id
            currentRoutes[personID]=route
        case "leaveEarly", "heatedAlternative", "cooledAlternative":
            let expected:HazardKind = command.kind == "leaveEarly" ? .flashFlood : command.kind == "heatedAlternative" ? .freezePowerLoss : .heatGridStrain
            guard scenario.hazard==expected,!(progress.supportsRefugeArrival && relocated),let destination=command.target,
                  household.transport.destinations.contains(where:{$0.id==destination && $0.conditionsConfirmed.confirmedValue==true}),
                  services[Svc.roads] == .operational,services[Svc.transport] == .operational,services[Svc.destination] == .operational else {throw SessionError.invalidCommand}
            // A recorded destination's conditions are exercise assumptions, never current activation.
            relocated=true
            flags.insert("exercise.destination.\(destination)")
        case "warmLayers":
            guard scenario.hazard == .freezePowerLoss,household.preparedness?.items["warmth"]?.available.confirmedValue==true else {throw SessionError.invalidCommand}
            if progress.supportsActionProgress,progress.protection=="recordedWarmth" {throw SessionError.invalidCommand}
            progress.protection="recordedWarmth"
        case "reduceSolarGain":
            if progress.supportsActionProgress,let room=command.target,progress.shadedRoomIDs.contains(room) {throw SessionError.invalidCommand}
            guard scenario.hazard == .heatGridStrain,let roomID=command.target,let home,home.space(roomID) != nil,
                  home.portals.contains(where:{$0.kind == .window && ($0.sideA == .space(roomID) || $0.sideB == .space(roomID))}) else {throw SessionError.invalidCommand}
            // Explicit exercise assumption; choosing this does not create an owned blind or medically safe room.
            if progress.usesRoomHeat,!progress.shadedRoomIDs.insert(roomID).inserted {throw SessionError.invalidCommand}
            progress.protection="exerciseShade|\(roomID)"
        default:throw SessionError.invalidCommand
        }
        hazardProgress=progress
        synchronizeAdaptiveOccupants()
    }
    func recordedPowerGaps()->[String] {
        guard hazardProgress?.supportsRecordedGapChecks==true else {return []}
        let powered=household.equipment.filter(\.requiresElectricalPower).map {"equipment.\($0.id)."}
        return unknowns.filter {id in id.hasPrefix("backup.") || powered.contains(where:id.hasPrefix)}.sorted()
    }
    func openHazardGaps()->[String] {
        switch scenario.hazard {
        case .homeFire:
            var gaps=currentRoutes.values.contains(where:{$0.primary==nil}) ? ["escapeRoute"]:[]
            if hazardProgress?.supportsEscapeAccompaniment==true {
                for person in household.people where person.needs.contains(.needsHelperToEvacuate) && hazardProgress?.outside.contains(person.id) != true {
                    let canAccompany=(home?.portals ?? []).contains {portal in
                        guard portal.sideA == .exterior || portal.sideB == .exterior else {return false}
                        var copy=self
                        return (try? copy.applyHazardAction(.init(kind:"accompanyEscape",target:person.id,value:portal.id))) != nil
                    }
                    if !canAccompany {gaps.append("escapeAssistance."+person.id)}
                }
            }
            return gaps
        case .tornado:return shelterSpace==nil ? ["shelterChoice"]:[]
        case .flashFlood:
            if hazardProgress?.supportsRefugeArrival==true,relocated {return []}
            var gaps:[String]=[]
            if services[Svc.roads] != .operational {gaps.append("departureAccess")}
            if hazardProgress?.supportsRefugeArrival==true {
                let missing=household.people.filter {person in
                    guard let route=currentRoutes[person.id] else {return true}
                    return route.request.purpose != .higherRefuge || route.primary == nil
                }.map(\.id).sorted()
                if !missing.isEmpty {gaps.append("higherRefuge");gaps += missing.map{"higherRefuge."+$0}}
            } else if !currentRoutes.values.contains(where:{$0.request.purpose == .higherRefuge && $0.primary != nil}) {gaps.append("higherRefuge")}
            return gaps
        case .freezePowerLoss:return (services[Svc.heat] != .operational ? ["heatContinuity"]:[])+recordedPowerGaps()
        case .heatGridStrain:
            var gaps=services[Svc.cooling] != .operational ? ["coolingContinuity"]:[]
            if hazardProgress?.usesRoomHeat==true,hazardProgress?.roomCoverageUnknown==true {gaps.append("roomCoolingCoverage")}
            return gaps+recordedPowerGaps()
        case .waterOutage:
            var gaps:[String]=[]
            if advisory != nil {gaps.append("waterQualityOrService")}
            if storedWater==nil || storedWater==0 {gaps.append("storedWater")}
            return gaps
        }
    }
    func feasibleHazardCommands()->[SessionCommand] {
        if hazardProgress?.supportsRefugeArrival==true,scenario.hazard == .flashFlood,relocated {return []}
        var candidates:[SessionCommand]=[]
        for person in household.people {
            for portal in home?.portals ?? [] where portal.sideA == .exterior || portal.sideB == .exterior {
                candidates.append(.init(kind:"escape",target:person.id,value:portal.id))
                if hazardProgress?.supportsEscapeAccompaniment==true {candidates.append(.init(kind:"accompanyEscape",target:person.id,value:portal.id))}
            }
            candidates.append(.init(kind:"accountOutside",target:person.id))
            if let shelter=shelterSpace {candidates.append(.init(kind:"reachShelter",target:person.id,value:shelter.id))}
            if hazardProgress?.supportsRefugeArrival==true,let route=currentRoutes[person.id],route.request.purpose == .higherRefuge,let destination=route.request.destinationSpaceID {
                candidates.append(.init(kind:"reachHigherRefuge",target:person.id,value:destination))
            }
            if let helper=person.helperPersonID {candidates.append(.init(kind:"accompanyShelter",target:person.id,value:helper))}
        }
        for destination in household.transport.destinations {
            for kind in ["leaveEarly","heatedAlternative","cooledAlternative"] {candidates.append(.init(kind:kind,target:destination.id))}
        }
        candidates.append(.init(kind:"warmLayers"))
        for room in home?.spaces ?? [] {candidates.append(.init(kind:"reduceSolarGain",target:room.id))}
        for gap in openHazardGaps() {candidates.append(.init(kind:"identifyGap",target:gap))}
        var valid=candidates.filter { command in var copy=self;return (try? copy.applyHazardAction(command)) != nil }
        if scenario.hazard == .tornado,services[Svc.handset] == .operational,services[Svc.cellular] == .operational {
            for contact in household.contacts where contact.isComplete {valid.append(.init(kind:"contact",target:contact.id))}
        }
        if scenario.hazard == .waterOutage {
            for source in ["tap","recordedStored"] {
                for activity in ["drink","prepareFood","hygiene","boiledDrink"] {
                    let command=SessionCommand(kind:"useWater",target:source,value:activity,quantityLiters:0.25)
                    var copy=self
                    let result:Void? = source == "tap" ? try? copy.useTapWater(command) : try? copy.useRecordedWater(command)
                    if result != nil {valid.append(command)}
                }
            }
        }
        if scenario.hazard == .freezePowerLoss || scenario.hazard == .heatGridStrain {
            for equipment in household.equipment {
                for source in equipment.compatibleBackupIDs where household.backupPower.contains(where:{$0.id==source}) {
                    valid.append(.init(kind:"allocatePower",target:equipment.id,value:source))
                }
                valid.append(.init(kind:"allocatePower",target:equipment.id,value:"none"))
            }
        }
        return valid
    }
    func experience()->HazardExperience? {
        guard let progress=hazardProgress else {return nil}
        let scene:String,objective:String,actions:[String],next:String
        switch scenario.hazard {
        case .homeFire:
            scene="smoke-egress-accounting";objective="Exit by a supported clear path and account outside; never re-enter."
            actions=["escape","accountOutside","closeDoor"]+(progress.supportsEscapeAccompaniment ? ["accompanyEscape"]:[]);next="prep.fireDrill"
        case .tornado:
            scene="warning-shelter-exposure";objective="Reach the recorded suitable shelter and maintain warning access."
            actions=["reachShelter","accompanyShelter","contact"];next="prep.shelterPlan"
        case .flashFlood:
            scene="rising-water-access";objective="Use a supported early departure before access is lost; never cross water."
            actions=["leaveEarly","moveTo","takeSupply"]+(progress.supportsRefugeArrival ? ["reachHigherRefuge","transferSupply"]:[]);next=progress.supportsRefugeArrival ? "prep.floodPlan":"prep.relocation"
        case .freezePowerLoss:
            scene="cold-continuity-energy";objective="Maintain documented essential loads and compare warmth or a recorded alternative."
            actions=["allocatePower","warmLayers","heatedAlternative"];next="prep.medicalBackup"
        case .heatGridStrain:
            scene="heat-cooling-access";objective="Maintain workable cooling and adapt when it becomes unavailable."
            actions=["reduceSolarGain","cooledAlternative","allocatePower"];next=progress.supportsRefugeArrival ? "prep.heatCold":"prep.coolingPlan"
        case .waterOutage:
            scene="service-advisory-water-use";objective="Match each activity to an allowed accessible supply and conserve recorded stock."
            actions=["useWater","choose","takeSupply"];next="prep.water"
        }
        let refuge=progress.supportsRefugeArrival && scenario.hazard == .flashFlood && !relocated ? currentRoutes.values.filter{$0.request.purpose == .higherRefuge && $0.primary != nil}.compactMap{ $0.request.destinationSpaceID }.sorted().first:nil
        let refuged=refuge.map {destination in household.people.filter{startSpace(for:$0)==destination}.map(\.id).sorted()}
        let sheltered=scenario.hazard == .tornado ? household.people.filter{startSpace(for:$0)==shelterSpace?.id}.map(\.id).sorted() : []
        let eventIDs=events.filter{$0.evidence.ruleID.hasPrefix("session.user") || $0.evidence.ruleID.hasPrefix("rule.choice")}.map(\.id)
        var facts=[HazardDebriefFact(kind:scene,subjectIDs:household.people.map(\.id),eventIDs:eventIDs,nextActionID:next)]
        if scenario.hazard == .homeFire {facts.append(.init(kind:"outsideAccounting",subjectIDs:household.people.map(\.id).filter{!progress.accounted.contains($0)},eventIDs:eventIDs,nextActionID:progress.supportsRefugeArrival ? "prep.nearMeetup":"prep.meetingPoint"))}
        if scenario.hazard == .tornado {facts.append(.init(kind:"notYetSheltered",subjectIDs:household.people.map(\.id).filter{!sheltered.contains($0)},eventIDs:eventIDs,nextActionID:next))}
        // Debrief details come from the actual branch, not just its hazard title or model narration.
        func fact(_ kind:String,_ subjects:[String]=[],_ action:String?=nil) {
            facts.append(.init(kind:kind,subjectIDs:subjects.sorted(),eventIDs:eventIDs,nextActionID:action ?? next))
        }
        switch scenario.hazard {
        case .homeFire:
            if progress.supportsEscapeAccompaniment {
                for (person,helper) in progress.escapeHelperByPersonID.sorted(by:{$0.key<$1.key}) {fact("recordedAssistedEscape",[person,helper])}
                for gap in openHazardGaps() where gap.hasPrefix("escapeAssistance.") {fact("noSupportedEscapeAssistance",[String(gap.dropFirst("escapeAssistance.".count))])}
            }
            for person in household.people where !progress.outside.contains(person.id) {
                guard let route=currentRoutes[person.id] else {fact("escapeRouteUnassessed",[person.id]);continue}
                if route.primary==nil {fact("noSupportedEscape",[person.id])}
                else if route.alternativeStatus != .independent {fact("noIndependentSecondEscape",[person.id]+route.sharedChokepoints)}
                if !route.exclusions.isEmpty {fact("excludedEscapeConnections",[person.id]+route.exclusions.map(\.elementID))}
            }
        case .tornado:
            if let shelter=shelterSpace {fact("recordedShelterArrival",[shelter.id]+sheltered)}
            else {fact("noSuitableRecordedShelter")}
            if services[Svc.handset] != .operational || services[Svc.cellular] != .operational {fact("warningCommunicationUnavailable")}
        case .flashFlood:
            fact(relocated ? "earlyDepartureUsed":"stillAtHomeDuringFlood")
            if let refuge,let refuged {
                fact("recordedHigherRefugeArrival",[refuge]+refuged)
                let pending=household.people.map(\.id).filter{!refuged.contains($0) && currentRoutes[$0]?.primary != nil && currentRoutes[$0]?.request.purpose == .higherRefuge}
                if !pending.isEmpty {fact("notYetAtHigherRefuge",pending)}
            }
            if progress.supportsRefugeArrival,!relocated {
                let missing=household.people.map(\.id).filter{currentRoutes[$0]?.request.purpose != .higherRefuge || currentRoutes[$0]?.primary == nil}
                if !missing.isEmpty {fact("noSupportedRefugeApproach",missing)}
            }
            for gap in openHazardGaps() {fact("floodGap."+gap)}
        case .freezePowerLoss,.heatGridStrain:
            let conditioning=scenario.hazard == .freezePowerLoss ? Svc.heat:Svc.cooling
            if progress.usesRoomHeat {
                let state=services[conditioning] ?? .unknown
                let kind=state == .operational ? "conditioningAvailable":state == .degraded ? "conditioningReduced":state == .unavailable ? "conditioningUnavailable":"conditioningUnknown"
                fact(kind,[conditioning])
            } else {fact(services[conditioning] == .operational ? "conditioningAvailable":"conditioningUnavailable",[conditioning])}
            if scenario.hazard == .heatGridStrain,progress.usesRoomHeat,progress.roomCoverageUnknown {fact("roomCoolingCoverageUnknown")}
            let unpowered=household.equipment.filter{$0.isEssential && services[Svc.device($0.id)] != .operational}.map(\.id)
            if !unpowered.isEmpty {fact("essentialEquipmentContinuityUnresolved",unpowered)}
            if let protection=progress.protection {fact(protection == "recordedWarmth" ? "recordedWarmthUsed":"exerciseShadingSelected",progress.usesRoomHeat && scenario.hazard == .heatGridStrain ? progress.shadedRoomIDs.sorted():protection.split(separator:"|").dropFirst().map(String.init))}
            if relocated {fact("recordedThermalAlternativeUsed")}
            if progress.supportsRecordedGapChecks {
                let acknowledged=Set(recordedPowerGaps()).intersection(progress.identifiedGaps).sorted()
                for gap in acknowledged {fact("recordedDependencyGapIdentified",[gap],"prep.medicalBackup")}
            }
        case .waterOutage:
            if let advisory {fact("waterAdvisory."+advisory.rawValue)}
            fact(services[Svc.waterSupply] == .operational ? "tapServiceAvailable":"tapServiceUnavailable")
            if storedWater == nil {fact("storedWaterQuantityUnknown")}
            else if storedWater == 0 {fact("storedWaterDepleted")}
            if flags.contains(where:{$0.hasPrefix("exercise.water.stored.")}) {fact("storedWaterActivityDebited")}
        }
        for requirement in currentUnmet.sorted() {facts.append(.init(kind:requirement,subjectIDs:[],eventIDs:causes[requirement] ?? [],nextActionID:next))}
        return HazardExperience(mechanicsVersion:progress.mechanicsVersion,hazard:scenario.hazard,scene:scene,objective:objective,supportedActions:actions+["identifyGap"],feasibleCommands:feasibleHazardCommands(),outsidePersonIDs:progress.outside.sorted(),accountedPersonIDs:progress.accounted.sorted(),shelteredPersonIDs:sheltered,destinationIDs:household.transport.destinations.map(\.id),occupantRoomIDs:Dictionary(uniqueKeysWithValues:household.people.map{($0.id,progress.outside.contains($0.id) ? "exterior":startSpace(for:$0))}),shelterRoomID:shelterSpace?.id,escapeHelperByPersonID:progress.supportsEscapeAccompaniment ? progress.escapeHelperByPersonID:nil,refugeRoomID:refuge,refugedPersonIDs:refuged,relocated:relocated,
            temperature:[HazardKind.freezePowerLoss,.heatGridStrain].contains(scenario.hazard) ? (progress.usesRoomHeat && scenario.hazard == .heatGridStrain ? HazardProgress.roomRange(lowerC:progress.lowerC,upperC:progress.upperC):EducationalTemperature(lowerC:progress.lowerC,upperC:progress.upperC)):nil,
            waterAdvisory:advisory,waterService:services[Svc.waterSupply],availableWaterGallons:storedWater,selectedProtection:progress.protection,roomTemperatures:progress.usesRoomHeat && !progress.roomTemperatures.isEmpty ? progress.roomTemperatures:nil,shadedRoomIDs:progress.usesRoomHeat && scenario.hazard == .heatGridStrain ? progress.shadedRoomIDs.sorted():nil,conditioningService:progress.usesRoomHeat && [.freezePowerLoss,.heatGridStrain].contains(scenario.hazard) ? services[scenario.hazard == .freezePowerLoss ? Svc.heat:Svc.cooling]:nil,roomCoolingCoverageUnknown:progress.usesRoomHeat && scenario.hazard == .heatGridStrain && progress.roomCoverageUnknown ? true:nil,openGapIDs:openHazardGaps(),identifiedGapIDs:progress.identifiedGaps.sorted(),debrief:facts)
    }
}

extension RunState {
    func waterActivity(_ command:SessionCommand)throws->Double {
        guard let liters=command.quantityLiters,liters.isFinite,liters>0,liters<=20,
              ["drink","prepareFood","hygiene","boiledDrink"].contains(command.value ?? "") else {throw SessionError.invalidCommand}
        return liters
    }
    mutating func useTapWater(_ command:SessionCommand)throws {
        _=try waterActivity(command)
        guard services[Svc.waterSupply] == .operational else {throw SessionError.invalidCommand}
        switch command.value {
        case "boiledDrink":guard advisory == .boilWater,homePowerUp else {throw SessionError.invalidCommand}
        case "hygiene":guard advisory == .boilWater || (advisory == nil && tapWaterUsable) else {throw SessionError.invalidCommand}
        default:guard advisory == nil,tapWaterUsable else {throw SessionError.invalidCommand}
        }
        flags.insert("exercise.water.tap.\(command.value!)")
    }
    mutating func useRecordedWater(_ command:SessionCommand)throws {
        let liters=try waterActivity(command)
        guard command.target == "recordedStored",let amount=storedWater,amount*3.785411784+1e-9>=liters else {throw SessionError.invalidCommand}
        storedWater=max(0,amount-liters/3.785411784)
        flags.insert("exercise.water.stored.\(command.value!)")
    }
}
extension SessionSupplyLedger {
    mutating func consumeWater(_ command:SessionCommand,run:inout RunState)throws {
        let liters=try run.waterActivity(command)
        guard let index=state.items.firstIndex(where:{$0.id==command.target && $0.category=="water" && $0.accessible==true}),
              let remaining=state.items[index].remaining else {throw SessionError.invalidCommand}
        let factor=state.items[index].unit == .usGallon ? 3.785411784 : 1.0
        guard remaining*factor+1e-9>=liters else {throw SessionError.invalidCommand}
        state.items[index].remaining=max(0,remaining-liters/factor)
        state.items[index].consumed += liters/factor
        // This item deduction is already settled; do not deduct it again at synchronize.
        if let projected=projectedGallons {projectedGallons=max(0,projected-liters/3.785411784);run.storedWater=projectedGallons}
        run.flags.insert("exercise.water.stored.\(command.value!)")
    }
}
