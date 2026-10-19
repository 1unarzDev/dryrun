import {intentRequest,intentContext,userCommand,userActionIntent} from '../src/intents.js';
import {practiceSource,practiceObservation} from '../src/practice-contracts.js';
import {directorProposalEnvelope,nextBoundary,presentationIntent} from '../src/director-envelope.js';
import {mkdir,writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {roleSchemas,featureContext,imageManifest,resourcePlan} from '../src/features.js';
import {operationRequest,continuationRequest,directorOutput,directorPolicy,directorState,command,previewConsequences,exerciseAssistance} from '../src/contracts.js';
await mkdir('../../content/ai/contracts',{recursive:true});
for(const [name,schema] of Object.entries({intentRequest,intentContext,userCommand,userActionIntent,practiceSource,practiceObservation,...roleSchemas,featureContext,imageManifest,resourcePlan,operationRequest,continuationRequest,directorOutput,directorPolicy,directorState,command,previewConsequences,exerciseAssistance,directorProposalEnvelope,nextBoundary,presentationIntent}))await writeFile('../../content/ai/contracts/'+name+'-v1.schema.json',JSON.stringify(z.toJSONSchema(schema),null,2)+'\n');
