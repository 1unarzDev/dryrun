import Foundation

/// Cloud-minimized action identity derived from the validated host log, never from a UI label.
public struct CommittedUserActionContext:Codable,Sendable,Equatable {
    public var contractVersion:String
    public var id:String
    public var kind:String
    public var target:String?
    public var value:String?
    public var quantityLiters:Double?
    public var commitRevision:Int
    public var commandIndex:Int
}
public extension SimulationSession {
    func userActionContexts(library:ScenarioLibrary,limit:Int=8)throws->[CommittedUserActionContext] {
        guard (1...8).contains(limit) else {throw SessionError.invalidCommand}
        _=try query(library:library)
        var actions:[CommittedUserActionContext]=[]
        for (revision,commit) in commits.enumerated() where commit.actor=="user" {
            for (index,command) in commit.commands.enumerated() {
                // Ignore extraneous command fields, even if the host did not use them. In particular
                // unsupported actions must never forward arbitrary submitted text as target/value.
                let targetKinds=["accompanyEscape","accompanyShelter","identifyGap","allocatePower","assignHelper","moveTo","takeSupply","transferSupply","contact","choose","closeDoor","escape","accountOutside","reachHigherRefuge","reachShelter","leaveEarly","heatedAlternative","cooledAlternative","reduceSolarGain","useWater"]
                let valueKinds=["accompanyEscape","accompanyShelter","allocatePower","assignHelper","moveTo","takeSupply","transferSupply","choose","closeDoor","useStoredWater","escape","reachHigherRefuge","reachShelter","useWater"]
                actions.append(CommittedUserActionContext(contractVersion:"dryrun.committed-action-context/1",id:commit.id,kind:command.kind,
                    target:targetKinds.contains(command.kind) ? command.target:nil,value:valueKinds.contains(command.kind) ? command.value:nil,
                    quantityLiters:command.kind == "useWater" ? command.quantityLiters:nil,commitRevision:revision+1,commandIndex:index))
            }
        }
        return Array(actions.suffix(limit))
    }
}
