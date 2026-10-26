import {it,expect} from 'vitest';
import {z} from 'zod';
import {codexStrictSchema,omitWireOptionalNulls} from '../src/codex-schema.js';
it('round-trips required-null and optional nested domain fields through strict runtime output',()=>{
 const host=z.object({question:z.string().nullable(),observations:z.array(z.object({category:z.enum(['water','light']),preparationKind:z.enum(['flashlight']).nullable().optional(),quantity:z.number().nullable()} ).strict())}).strict();
 const schema=z.toJSONSchema(host);const wire=codexStrictSchema(schema);
 const valid={question:null,observations:[{category:'light',preparationKind:null,quantity:1}]};
 expect(host.parse(omitWireOptionalNulls(valid,schema))).toEqual({question:null,observations:[{category:'light',quantity:1}]});
 const item=(wire.properties as any).observations.items;expect(item.required).toContain('preparationKind');
 // Host authority still rejects invented enum values and wrong quantities.
 expect(()=>host.parse(omitWireOptionalNulls({question:null,observations:[{category:'invented',preparationKind:null,quantity:'ten'}]},schema))).toThrow();
});
it('normalizes nullable optionals inside discriminated union branches without erasing required null',()=>{
 const host=z.object({result:z.discriminatedUnion('kind',[z.object({kind:z.literal('a'),optional:z.number().optional(),required:z.string().nullable()}).strict(),z.object({kind:z.literal('b'),value:z.boolean()}).strict()])}).strict();
 expect(host.parse(omitWireOptionalNulls({result:{kind:'a',optional:null,required:null}},z.toJSONSchema(host)))).toEqual({result:{kind:'a',required:null}});
});

import {preparationOutput,preparationDestination,roleSchemas} from '../src/features.js';
it('projects every real role schema recursively without unsupported exclusive unions',()=>{
 const inspect=(value:unknown):void=>{if(!value||typeof value!=='object')return;if(Array.isArray(value)){value.forEach(inspect);return;}const object=value as Record<string,unknown>;expect(Object.keys(object)).not.toContain('oneOf');Object.values(object).forEach(inspect);};
 for(const host of Object.values(roleSchemas))inspect(codexStrictSchema(z.toJSONSchema(host)));
 const schema=z.toJSONSchema(preparationOutput);const wire=codexStrictSchema(schema);
 expect(JSON.stringify(wire)).toContain('contactRole');expect(JSON.stringify(wire)).toContain('checklistID');
 for(const destination of [{kind:'contact',contactRole:'careProvider'},{kind:'family',subjectID:null},{kind:'equipment',subjectID:'equipment-a'},{kind:'meeting',purpose:'outsideMeetingPoint'},{kind:'checklist',checklistID:'check-a',titleKey:'title-a'},{kind:'water'}]){
  const normalized=omitWireOptionalNulls(destination,z.toJSONSchema(preparationDestination));expect(preparationDestination.parse(normalized).kind).toBe(destination.kind);
 }
 expect(()=>preparationDestination.parse({kind:'equipment',subjectID:null})).toThrow();expect(()=>preparationDestination.parse({kind:'water',invented:true})).toThrow();
});
it('rejects ambiguous exclusive union instead of broadening host semantics',()=>{
 expect(()=>codexStrictSchema({oneOf:[{type:'number'},{type:'integer'}]})).toThrow('codex_schema_unsupported_union');
});
