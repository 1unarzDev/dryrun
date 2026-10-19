import Foundation
import Testing
@testable import DryRunCore

@Suite("Submitted user intent boundary") struct UserActionIntentTests {
    func source()throws->(SimulationSession,ActionSubmission,UserActionIntent) {
        let session=try SimulationSession.initialize(id:"intent",initial:SimFixtures.input(SampleHouseholds.oak,"water-outage"),library:SimFixtures.library)
        let receipt=try session.query(library:SimFixtures.library)
        let binding=AgentContextBinding(receipt:receipt,householdRevision:session.initial.household.revision,homeRevision:session.initial.home!.revision)
        let input=ActionSubmission(id:"input-1",text:"Use stored water only for drinking and cooking.",binding:binding)
        return (session,input,UserActionIntent(contractVersion:"dryrun.user-intent/1",submittedInputID:input.id,inputDigest:input.inputDigest,binding:binding,status:.proposed,commands:[.init(kind:"useStoredWater",value:"essential")]))
    }
    @Test func commitsActualInputOnceAndReplaysWithoutTranscript()throws {
        var (session,input,intent)=try source()
        let result=try intent.commit(submission:input,to:&session,library:SimFixtures.library)
        #expect(result.status=="committed");#expect(session.commits[0].actor=="user")
        #expect(session.commits[0].id==input.id)
        #expect(throws:SessionError.stale){try intent.commit(submission:input,to:&session,library:SimFixtures.library)}
        let serialized=try DryRunJSON.encoder().encode(session)
        #expect(!String(decoding:serialized,as:UTF8.self).contains(input.text))
        let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:serialized)
        #expect(try restored.query(library:SimFixtures.library)==result.receipt)
    }
    @Test func rejectsWrongInputSourceDirectorCommandsAndClarification()throws {
        var (session,input,intent)=try source()
        var changed=intent;changed.submittedInputID="different"
        #expect(throws:SessionError.invalidCommand){try changed.commit(submission:input,to:&session,library:SimFixtures.library)}
        changed=intent;changed.inputDigest="different"
        #expect(throws:SessionError.invalidCommand){try changed.commit(submission:input,to:&session,library:SimFixtures.library)}
        for command in [SessionCommand(kind:"advance",minute:1),.init(kind:"startIncident",target:"x",minute:0,hazard:.homeFire),.init(kind:"useStoredWater",value:"essential",minute:1)] {
            changed=intent;changed.commands=[command]
            #expect(throws:SessionError.invalidCommand){try changed.commit(submission:input,to:&session,library:SimFixtures.library)}
        }
        changed=intent;changed.status = .needsClarification;changed.commands=nil;changed.question="Which person?"
        #expect(throws:SessionError.invalidCommand){try changed.commit(submission:input,to:&session,library:SimFixtures.library)}
        #expect(session.revision==0)
    }
    @Test func infeasibleCompoundHasNoPartialEffectsAndNoDefaultChoice()throws {
        var (session,input,intent)=try source()
        intent.commands=[.init(kind:"useStoredWater",value:"all"),.init(kind:"allocatePower",target:"invented",value:"invented")]
        let result=try intent.commit(submission:input,to:&session,library:SimFixtures.library)
        #expect(result.status=="unsupportedAttempt")
        #expect(session.commits[0].commands==[.init(kind:"unsupported")])
        #expect(session.commits[0].id==input.id)
        #expect(result.receipt.snapshot.simMinute==0)
        #expect(session.initial.household==SampleHouseholds.oak)
    }
    @Test func persistenceFailureCannotBeReinterpretedAsUnsupported()throws {
        var (session,input,intent)=try source()
        var calls=0
        #expect(throws:SessionError.invalidCommand){try intent.commit(submission:input,to:&session,library:SimFixtures.library,persist:{_ in calls+=1;throw SessionError.invalidCommand})}
        #expect(calls==1);#expect(session.revision==0)
    }
}
