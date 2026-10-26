import Foundation

extension RunState {
    func isOutside(_ personID: String) -> Bool {
        hazardProgress?.outside.contains(personID) ?? (occupants[personID]?.exteriorExitPortalID != nil)
    }

    mutating func synchronizeOccupants() {
        if hazardProgress != nil { synchronizeAdaptiveOccupants() }
        for person in household.people where occupants[person.id] == nil {
            let room = startSpace(for: person)
            occupants[person.id] = .init(personID: person.id, currentSpaceID: room == "unknown" ? nil : room)
        }
        spatialState?.occupants = occupants.keys.sorted().compactMap { occupants[$0] }
    }

    /// Adaptive commands retain HazardProgress as authority. This is only the
    /// existing renderer's snapshot projection, not a second set of arrival rules.
    mutating func synchronizeAdaptiveOccupants() {
        guard let progress = hazardProgress else { return }
        for person in household.people {
            if progress.outside.contains(person.id) {
                let exit = occupants[person.id]?.exteriorExitPortalID ?? currentRoutes[person.id]?.primary?.exitPortalID
                occupants[person.id] = .init(personID: person.id, exteriorExitPortalID: exit,
                    accountedOutside: progress.accounted.contains(person.id))
            } else {
                let room = startSpace(for: person)
                occupants[person.id] = .init(personID: person.id, currentSpaceID: room == "unknown" ? nil : room,
                    shelteredSpaceID: scenario.hazard == .tornado && room == shelterSpace?.id ? room : nil)
            }
        }
    }

    /// Resolve all candidates against the same pre-action positions. A dependent occupant
    /// requires a reachable recorded helper; a shared helper's simultaneous capacity is unknown.
    func canAssist(_ person: Person, exclusions: ScenarioExclusions, destination: String? = nil, exitPortalID: String? = nil) -> Bool {
        let dependent = person.needs.contains(.needsHelperToEvacuate) || person.ageBand == .child || person.ageBand == .infant
        guard dependent else { return true }
        guard let home, let helperID = person.helperPersonID,
              let helper = household.people.first(where: { $0.id == helperID }),
              !isOutside(helperID), helperID != person.id,
              !helper.needs.contains(.needsHelperToEvacuate), helper.ageBand != .child, helper.ageBand != .infant,
              household.people.filter({ $0.helperPersonID == helperID }).count == 1 else { return false }
        guard planner.plan(.init(personID: helperID, startSpaceID: startSpace(for: helper), mobility: mobility(for: helper),
            exclusions: exclusions, purpose: .helperReach, destinationSpaceID: startSpace(for: person)), in: home).primary != nil else { return false }
        // Reaching the person is insufficient if the helper cannot continue to the same objective.
        let purpose: RoutePurpose = destination == nil ? .outdoorEgress : .interiorShelter
        var continuationExclusions = exclusions
        if let exitPortalID {
            continuationExclusions.blockedPortalIDs = Array(Set(exclusions.blockedPortalIDs + home.portals.filter {
                $0.leadsToExterior && $0.id != exitPortalID
            }.map(\.id))).sorted()
        }
        let continuation = planner.plan(.init(personID: helperID, startSpaceID: startSpace(for: person), mobility: mobility(for: helper),
            exclusions: continuationExclusions, purpose: purpose, destinationSpaceID: destination), in: home)
        guard let path = continuation.primary else { return false }
        if let exitPortalID {
            return path.exitPortalID == exitPortalID
        }
        return true
    }

    mutating func applySpatialChoice(_ option: AuthoredOption, choice: ChoicePoint, cause: String) {
        guard hazardProgress == nil, let home, spatialState != nil else { return }
        synchronizeOccupants()
        let exclusions = ScenarioExclusions(blockedSpaceIDs: spatialState?.affectedSpaceIDs ?? [],
                                            blockedPortalIDs: spatialState?.affectedPortalIDs ?? [])
        if option.effect == "takeExit", scenario.hazard == .homeFire {
            if choice.id == "choice.home-fire.outside" {
                // Accounting cannot evacuate a person who remained inside.
                for person in household.people where isOutside(person.id) {
                    occupants[person.id]?.accountedOutside = true
                }
            } else {
                let candidates = household.people.filter { !isOutside($0.id) }.compactMap { person -> (Person, RouteResult)? in
                    let route = planner.plan(.init(personID: person.id, startSpaceID: startSpace(for: person),
                        mobility: mobility(for: person), exclusions: exclusions), in: home)
                    guard let path = route.primary, canAssist(person, exclusions: exclusions, exitPortalID: path.exitPortalID) else { return nil }
                    return (person, route)
                }
                for (person, route) in candidates {
                    occupants[person.id] = .init(personID: person.id, exteriorExitPortalID: route.primary!.exitPortalID)
                    currentRoutes[person.id] = route // Traversed geometry, not a new route back inside.
                    resolveSticky("req.egress.\(person.id)")
                    resolveSticky("req.assistance.reach.\(person.id)")
                }
                // A reachable helper accompanies the dependent through the same verified
                // exit rather than simultaneously taking their independently shortest exit.
                for (person, route) in candidates where person.needs.contains(.needsHelperToEvacuate) || person.ageBand == .child || person.ageBand == .infant {
                    guard let helperID = person.helperPersonID,
                          isOutside(helperID), let exit = route.primary?.exitPortalID else { continue }
                    occupants[helperID]?.exteriorExitPortalID = exit
                }
            }
        } else if option.effect == "goToShelter", scenario.hazard == .tornado,
                  household.housing.homeType != .manufacturedHome, let shelter = shelterSpace {
            let candidates = household.people.filter { !isOutside($0.id) }.compactMap { person -> (Person, RouteResult)? in
                guard canAssist(person, exclusions: exclusions, destination: shelter.id) else { return nil }
                let route = planner.plan(.init(personID: person.id, startSpaceID: startSpace(for: person), mobility: mobility(for: person),
                    exclusions: exclusions, purpose: .interiorShelter, destinationSpaceID: shelter.id), in: home)
                return route.primary == nil ? nil : (person, route)
            }
            for (person, _) in candidates {
                let index = household.people.firstIndex { $0.id == person.id }!
                household.people[index].sleepingSpaceID = shelter.id
                var options = input.effectiveSpatialOptions
                options.startingSpaceIDs[person.id] = shelter.id
                input.spatialOptions = options
                occupants[person.id] = .init(personID: person.id, currentSpaceID: shelter.id, shelteredSpaceID: shelter.id)
                currentRoutes[person.id] = planner.plan(.init(personID: person.id, startSpaceID: shelter.id, mobility: mobility(for: person),
                    exclusions: exclusions, purpose: .interiorShelter, destinationSpaceID: shelter.id), in: home)
            }
            if household.people.allSatisfy({ occupants[$0.id]?.shelteredSpaceID == shelter.id }) { resolveSticky("req.shelter") }
        }
        if spatialState != nil {
            spatialState?.stageID = cause
            spatialState?.routes = currentRoutes.keys.sorted().compactMap { currentRoutes[$0] }
            spatialState?.occupants = occupants.keys.sorted().compactMap { occupants[$0] }
        }
    }
}
