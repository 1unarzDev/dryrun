/** Runtime wire constraints, separate from host/domain schema authority. */
export function codexStrictSchema(schema:Record<string,unknown>):Record<string,unknown>{
 const result:Record<string,unknown>={};
 for(const [key,value]of Object.entries(schema)){
  if(key==='$schema')continue;
  if(key==='properties'&&value&&typeof value==='object'){
   const required=Array.isArray(schema.required)?schema.required:[];
   result.properties=Object.fromEntries(Object.entries(value).map(([name,child])=>{
    const projected=codexStrictSchema(child as Record<string,unknown>);
    return [name,required.includes(name)?projected:{anyOf:[projected,{type:'null'}]}];
   }));
   result.required=Object.keys(value);result.additionalProperties=false;
  }else if(key==='required'&&schema.properties)continue;
  else if(key==='additionalProperties'&&schema.properties)continue;
  else if(key==='oneOf'&&Array.isArray(value)){
   // Literal discriminators make these branches disjoint, preserving oneOf semantics.
   const branches=value as Record<string,unknown>[];
   const discriminators=(branch:Record<string,unknown>)=>Object.entries((branch.properties??{}) as Record<string,Record<string,unknown>>).filter(([name,field])=>Array.isArray(branch.required)&&branch.required.includes(name)&&Object.hasOwn(field,'const'));
   if(!branches.every((a,i)=>branches.slice(i+1).every(b=>discriminators(a).some(([name,field])=>discriminators(b).some(([other,candidate])=>other===name&&JSON.stringify(field.const)!==JSON.stringify(candidate.const))))))throw new Error('codex_schema_unsupported_union');
   result.anyOf=branches.map(branch=>codexStrictSchema(branch));
  }
  else if(Array.isArray(value)&&['anyOf','allOf','prefixItems'].includes(key))result[key]=value.map(v=>codexStrictSchema(v as Record<string,unknown>));
  else if(value&&typeof value==='object'&&!Array.isArray(value)&&['items','additionalProperties'].includes(key))result[key]=codexStrictSchema(value as Record<string,unknown>);
  else if(key==='$defs'&&value&&typeof value==='object')result[key]=Object.fromEntries(Object.entries(value).map(([name,child])=>[name,codexStrictSchema(child as Record<string,unknown>)]));
  else result[key]=value;
 }
 return result;
}
/** Null introduced only by the wire projection means an omitted optional field to the host. */
export function omitWireOptionalNulls(value:unknown,schema:Record<string,unknown>):unknown{
 const alternatives=schema.anyOf??schema.oneOf;
 if(Array.isArray(alternatives)){
  const match=alternatives.find(branch=>{
   if(!branch||typeof branch!=='object')return false;const b=branch as Record<string,unknown>;
   const type=value===null?'null':Array.isArray(value)?'array':typeof value==='object'?'object':typeof value==='number'?'number':typeof value;
   if(b.type!==undefined&&b.type!==type&&!(Array.isArray(b.type)&&b.type.includes(type)))return false;
   if('const'in b&&b.const!==value)return false;
   if(value&&typeof value==='object'&&!Array.isArray(value)&&b.properties&&typeof b.properties==='object')for(const [key,property]of Object.entries(b.properties))if(property&&typeof property==='object'&&'const'in property&&Reflect.get(value,key)!==property.const)return false;
   return true;
  });if(match)return omitWireOptionalNulls(value,match as Record<string,unknown>);
 }
 if(Array.isArray(value)&&schema.items&&typeof schema.items==='object')return value.map(item=>omitWireOptionalNulls(item,schema.items as Record<string,unknown>));
 if(value&&typeof value==='object'&&!Array.isArray(value)&&schema.properties&&typeof schema.properties==='object'){
  const properties=schema.properties as Record<string,Record<string,unknown>>,required=Array.isArray(schema.required)?schema.required:[];
  return Object.fromEntries(Object.entries(value).flatMap(([key,child])=>child===null&&properties[key]&&!required.includes(key)?[]:[[key,properties[key]?omitWireOptionalNulls(child,properties[key]):child]]));
 }
 return value;
}
