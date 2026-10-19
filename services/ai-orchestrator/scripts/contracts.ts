import {mkdir,writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {roleSchemas,featureContext,imageManifest,resourcePlan} from '../src/features.js';
import {operationRequest,continuationRequest,directorOutput} from '../src/contracts.js';
await mkdir('../../content/ai/contracts',{recursive:true});
for(const [name,schema] of Object.entries({...roleSchemas,featureContext,imageManifest,resourcePlan,operationRequest,continuationRequest,directorOutput}))await writeFile('../../content/ai/contracts/'+name+'-v1.schema.json',JSON.stringify(z.toJSONSchema(schema),null,2)+'\n');
