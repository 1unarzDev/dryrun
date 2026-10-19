import {directorProposalEnvelope,nextBoundary,presentationIntent} from '../src/director-envelope.js';
import {mkdir,writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {roleSchemas,featureContext,imageManifest,resourcePlan} from '../src/features.js';
import {operationRequest,continuationRequest,directorOutput,directorPolicy,directorState,command,previewConsequences} from '../src/contracts.js';
await mkdir('../../content/ai/contracts',{recursive:true});
for(const [name,schema] of Object.entries({...roleSchemas,featureContext,imageManifest,resourcePlan,operationRequest,continuationRequest,directorOutput,directorPolicy,directorState,command,previewConsequences,directorProposalEnvelope,nextBoundary,presentationIntent}))await writeFile('../../content/ai/contracts/'+name+'-v1.schema.json',JSON.stringify(z.toJSONSchema(schema),null,2)+'\n');
