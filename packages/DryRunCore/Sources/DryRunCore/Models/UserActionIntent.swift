import Foundation

public struct ActionSubmission:Codable,Sendable {
    public var id:String
    public var text:String
    public var binding:AgentContextBinding
    public init(id:String,text:String,binding:AgentContextBinding){self.id=id;self.text=text;self.binding=binding}
    public var inputDigest:String {StableDigest.of(Data(text.utf8))}
}
public enum UserIntentStatus:String,Codable,Sendable {case proposed,needsClarification,unsupported}
public struct IntentCommitReceipt:Codable,Sendable {
    public var status:String
    public var receipt:SessionReceipt
}
/// Interpretation of one explicitly submitted optional text/voice action. Never a household edit.
public struct UserActionIntent:Codable,Sendable {
    public var contractVersion:String
    public var submittedInputID:String
    public var inputDigest:String
    public var binding:AgentContextBinding
    public var status:UserIntentStatus
    public var commands:[SessionCommand]?
    public var question:String?
    public func commit(submission:ActionSubmission,to session:inout SimulationSession,library:ScenarioLibrary,
        persist:(SimulationSession)throws->Void={_ in})throws->IntentCommitReceipt {
        guard contractVersion=="dryrun.user-intent/1",!submission.id.isEmpty,submission.id.count<=120,
              !submission.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,submission.text.utf8.count<=4000,
              submittedInputID==submission.id,inputDigest==submission.inputDigest,binding==submission.binding else {throw SessionError.invalidCommand}
        try binding.validate(receipt:session.query(library:library),household:session.initial.household,home:session.initial.home)
        guard status != .needsClarification,question==nil else {throw SessionError.invalidCommand}
        if status == .unsupported {
            guard commands==nil else {throw SessionError.invalidCommand}
            let receipt=try session.commit(.init(id:submission.id,actor:"user",baseRevision:binding.revision,commands:[.init(kind:"unsupported")]),library:library,persist:persist)
            return IntentCommitReceipt(status:"unsupportedAttempt",receipt:receipt)
        }
        guard let commands,!commands.isEmpty,commands.count<=3 else {throw SessionError.invalidCommand}
        for command in commands {
            guard command.minute==nil,command.hazard==nil,command.durationMinutes==nil else {throw SessionError.invalidCommand}
            switch command.kind {
            case "moveTo","takeSupply","transferSupply","assignHelper","allocatePower","closeDoor","choose":
                guard command.target?.isEmpty==false,command.value?.isEmpty==false else {throw SessionError.invalidCommand}
            case "contact":guard command.target?.isEmpty==false,command.value==nil else {throw SessionError.invalidCommand}
            case "useStoredWater":guard command.target==nil,["essential","all"].contains(command.value) else {throw SessionError.invalidCommand}
            case "finish":guard command.target==nil,command.value==nil,commands.count==1 else {throw SessionError.invalidCommand}
            default:throw SessionError.invalidCommand
            }
        }
        let proposed=SessionCommit(id:submission.id,actor:"user",baseRevision:binding.revision,commands:commands)
        var accepted=proposed
        var resultStatus="committed"
        do {_ = try session.preview(proposed,library:library)}
        catch SessionError.invalidCommand {
            // No partial movement/allocation/supply use is published. Persist outside this catch:
            // a storage error, even one typed invalidCommand, must never become an alternate action.
            accepted=SessionCommit(id:submission.id,actor:"user",baseRevision:binding.revision,commands:[.init(kind:"unsupported")])
            resultStatus="unsupportedAttempt"
        }
        let receipt=try session.commit(accepted,library:library,persist:persist)
        return IntentCommitReceipt(status:resultStatus,receipt:receipt)
    }
}
