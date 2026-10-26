export type CodexFailureKind='deadline'|'cancelled'|'throttled'|'invalid_schema'|'invalid_request'|'unsupported_capability'|'execution_budget'|'unavailable';
/** Only this finite metadata vocabulary may cross the runtime boundary. No message text. */
export class CodexFailure extends Error {constructor(readonly kind:CodexFailureKind){super('codex_'+kind);this.name='CodexFailure';}}
export function protocolFailure(metadata:unknown):CodexFailure {
 const root=metadata&&typeof metadata==='object'?metadata as Record<string,unknown>:{};
 const error=root.error&&typeof root.error==='object'?root.error as Record<string,unknown>:root;
 const info=error.codexErrorInfo??root.codexErrorInfo;
 const status=error.httpStatusCode??root.httpStatusCode;
 const variant=info&&typeof info==='object'?Object.values(info as Record<string,unknown>).find(v=>v&&typeof v==='object') as Record<string,unknown>|undefined:undefined;
 if(status===429||variant?.httpStatusCode===429||info==='rateLimitExceeded'||info==='usageLimitExceeded')return new CodexFailure('throttled');
 if(error.code===-32602||error.code==='invalid_schema'||error.code==='invalid_json_schema'||error.code==='schema_validation_error')return new CodexFailure('invalid_schema');
 if(error.code==='unsupported_capability'||error.code==='unsupported_tool'||error.code==='unsupported_image')return new CodexFailure('unsupported_capability');
 if(info==='badRequest')return new CodexFailure('invalid_request');
 return new CodexFailure('unavailable');
}
