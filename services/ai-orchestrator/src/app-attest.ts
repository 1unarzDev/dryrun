import {X509Certificate,createHash,createHmac,createPublicKey,randomBytes,timingSafeEqual,verify,type KeyObject} from 'node:crypto';

/**
 * App Attest installation sign-in (Apple, "Validating apps that connect to your server"):
 *   challenge (one-time, short-lived) → native attestKey over SHA256(challenge) → verifyAttestation stores the key
 *   → per session: challenge → native assertion over clientData {challenge, keyId, scope} → verifyAssertion
 *   → short-lived HMAC session token scoped to the gateway's allowed scope.
 * Keys, counters and challenges are held in memory here; a deployment needs a durable, per-installation store
 * (and rate limits in front of the unauthenticated endpoints). Session tokens never carry household data.
 */

/** Apple App Attestation Root CA (https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem). */
export const APPLE_APP_ATTEST_ROOT_PEM=`-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;
export const APPLE_APP_ATTEST_ROOT_SHA256='1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32';

export type AttestEnvironment='development'|'production';
const sha256=(...parts:Buffer[])=>createHash('sha256').update(Buffer.concat(parts)).digest();
const fail=(reason:string):never=>{throw new Error(reason);};

// Minimal CBOR (RFC 8949) for App Attest objects: ints, byte/text strings, arrays, maps. No tags or floats needed.
export function decodeCBOR(data:Buffer):unknown{
 let i=0;
 const length=(info:number):number=>{
  if(info<24)return info;
  const n=info===24?1:info===25?2:info===26?4:info===27?8:fail('cbor_length');
  if(i+n>data.length)fail('cbor_truncated');
  let v=0;for(let k=0;k<n;k++)v=v*256+data[i+k]!;i+=n;
  if(!Number.isSafeInteger(v))fail('cbor_length');return v;
 };
 const item=(depth:number):unknown=>{
  if(depth>8||i>=data.length)fail('cbor_truncated');
  const b=data[i++]!,major=b>>5,info=b&31;
  if(info===31)fail('cbor_indefinite');
  const n=length(info);
  switch(major){
   case 0:return n;
   case 1:return -1-n;
   case 2:case 3:{if(i+n>data.length)fail('cbor_truncated');const s=data.subarray(i,i+n);i+=n;return major===2?Buffer.from(s):new TextDecoder('utf-8',{fatal:true}).decode(s);}
   case 4:{if(n>64)fail('cbor_size');const a:unknown[]=[];for(let k=0;k<n;k++)a.push(item(depth+1));return a;}
   case 5:{if(n>64)fail('cbor_size');const m=new Map<unknown,unknown>();for(let k=0;k<n;k++){const key=item(depth+1);if(m.has(key))fail('cbor_duplicate_key');m.set(key,item(depth+1));}return m;}
   default:return fail('cbor_type');
  }
 };
 const out=item(0);if(i!==data.length)fail('cbor_trailing');return out;
}

/** Matching minimal encoder (tests, fixtures). */
export function encodeCBOR(v:unknown):Buffer{
 const head=(major:number,n:number)=>{
  if(n<24)return Buffer.from([major<<5|n]);
  if(n<256)return Buffer.from([major<<5|24,n]);
  if(n<65536)return Buffer.from([major<<5|25,n>>8,n&255]);
  const b=Buffer.alloc(5);b[0]=major<<5|26;b.writeUInt32BE(n,1);return b;
 };
 if(typeof v==='number'&&Number.isSafeInteger(v))return v>=0?head(0,v):head(1,-1-v);
 if(Buffer.isBuffer(v))return Buffer.concat([head(2,v.length),v]);
 if(typeof v==='string'){const b=Buffer.from(v,'utf8');return Buffer.concat([head(3,b.length),b]);}
 if(Array.isArray(v))return Buffer.concat([head(4,v.length),...v.map(encodeCBOR)]);
 if(v instanceof Map)return Buffer.concat([head(5,v.size),...[...v].flatMap(([k,x])=>[encodeCBOR(k),encodeCBOR(x)])]);
 return fail('cbor_type');
}

// DER walk to the App Attest nonce extension (1.2.840.113635.100.8.2): SEQUENCE { [1] { OCTET STRING nonce } }.
const NONCE_OID=Buffer.from('06092a864886f763640802','hex');
function der(buf:Buffer,at:number):{tag:number;start:number;end:number}{
 const tag=buf[at]!;let len=buf[at+1]!,start=at+2;
 if(len&0x80){const n=len&0x7f;if(n<1||n>3)fail('der_length');len=0;for(let k=0;k<n;k++)len=len*256+buf[start+k]!;start+=n;}
 if(start+len>buf.length)fail('der_truncated');
 return {tag,start,end:start+len};
}
export function attestationNonce(certDER:Buffer):Buffer{
 const at=certDER.indexOf(NONCE_OID);
 if(at<0||certDER.indexOf(NONCE_OID,at+1)>=0)fail('nonce_extension');
 let next=der(certDER,at+NONCE_OID.length);
 if(next.tag===0x01)next=der(certDER,next.end); // critical flag
 if(next.tag!==0x04)fail('nonce_extension');
 const seq=der(certDER,next.start);if(seq.tag!==0x30)fail('nonce_extension');
 const tagged=der(certDER,seq.start);if(tagged.tag!==0xa1)fail('nonce_extension');
 const octets=der(certDER,tagged.start);if(octets.tag!==0x04||octets.end-octets.start!==32)fail('nonce_extension');
 return certDER.subarray(octets.start,octets.end);
}

function uncompressedPoint(key:KeyObject):Buffer{
 const jwk=key.export({format:'jwk'});
 if(jwk.kty!=='EC'||jwk.crv!=='P-256'||!jwk.x||!jwk.y)fail('key_type');
 return Buffer.concat([Buffer.from([4]),Buffer.from(jwk.x!,'base64url'),Buffer.from(jwk.y!,'base64url')]);
}
const within=(cert:X509Certificate,now:Date)=>new Date(cert.validFrom)<=now&&now<=new Date(cert.validTo);

export class AppAttestVerifier{
 private readonly root:X509Certificate;
 private readonly rpIdHash:Buffer;
 constructor(readonly appID:string,readonly environment:AttestEnvironment,{rootPEM=APPLE_APP_ATTEST_ROOT_PEM,rootSHA256=APPLE_APP_ATTEST_ROOT_SHA256}:{rootPEM?:string;rootSHA256?:string}={}){
  if(!/^[A-Z0-9]{10}\.[A-Za-z0-9.-]{1,155}$/.test(appID))fail('app_id');
  this.root=new X509Certificate(rootPEM);
  if(this.root.fingerprint256!==rootSHA256)fail('root_pin');
  this.rpIdHash=sha256(Buffer.from(appID,'utf8'));
 }
 /** Steps 1–9 of Apple's attestation validation. Returns the credential public key and receipt to store. */
 verifyAttestation(keyIdB64:string,attestation:Buffer,clientDataHash:Buffer,now=new Date()):{publicKey:KeyObject;receipt:Buffer}{
  const keyId=Buffer.from(keyIdB64,'base64');if(keyId.length!==32)fail('key_id');
  const obj=decodeCBOR(attestation);
  if(!(obj instanceof Map)||obj.get('fmt')!=='apple-appattest')fail('format');
  const stmt=(obj as Map<unknown,unknown>).get('attStmt'),authData=(obj as Map<unknown,unknown>).get('authData');
  if(!(stmt instanceof Map)||!Buffer.isBuffer(authData))fail('format');
  const x5c=(stmt as Map<unknown,unknown>).get('x5c'),receipt=(stmt as Map<unknown,unknown>).get('receipt');
  if(!Array.isArray(x5c)||x5c.length!==2||!x5c.every(Buffer.isBuffer)||!Buffer.isBuffer(receipt))fail('format');
  // 1. Chain: credential certificate ← intermediate ← pinned Apple root, all valid now.
  const [cred,intermediate]=(x5c as Buffer[]).map(d=>new X509Certificate(d)) as [X509Certificate,X509Certificate];
  if(!cred.checkIssued(intermediate)||!cred.verify(intermediate.publicKey)||!intermediate.checkIssued(this.root)||!intermediate.verify(this.root.publicKey)
   ||!within(cred,now)||!within(intermediate,now)||!within(this.root,now)||intermediate.ca!==true)fail('chain');
  // 2–4. nonce = SHA256(authData ‖ clientDataHash) must equal the credential certificate's extension.
  if(clientDataHash.length!==32)fail('client_data');
  const nonce=attestationNonce((x5c as Buffer[])[0]!);
  if(!timingSafeEqual(nonce,sha256(authData as Buffer,clientDataHash)))fail('nonce');
  // 5. keyId = SHA256(credential public key, uncompressed point).
  const publicKey=cred.publicKey;
  if(!sha256(uncompressedPoint(publicKey)).equals(keyId))fail('key_id');
  // 6–9. authData: rpIdHash, counter 0, AAGUID for the environment, credentialId = keyId.
  const a=authData as Buffer;if(a.length<55+32)fail('auth_data');
  if(!a.subarray(0,32).equals(this.rpIdHash))fail('app_id');
  if(a.readUInt32BE(33)!==0)fail('counter');
  const aaguid=a.subarray(37,53),expected=this.environment==='production'?Buffer.concat([Buffer.from('appattest'),Buffer.alloc(7)]):Buffer.from('appattestdevelop');
  if(!aaguid.equals(expected))fail('environment');
  const idLength=a.readUInt16BE(53);if(idLength!==32||!a.subarray(55,55+idLength).equals(keyId))fail('credential_id');
  return {publicKey,receipt:receipt as Buffer};
 }
 /** Apple's assertion validation: signature over SHA256(authenticatorData ‖ SHA256(clientData)), app ID, rising counter. */
 verifyAssertion(assertion:Buffer,clientData:Buffer,publicKey:KeyObject,previousCounter:number):number{
  const obj=decodeCBOR(assertion);
  if(!(obj instanceof Map))fail('format');
  const signature=(obj as Map<unknown,unknown>).get('signature'),authData=(obj as Map<unknown,unknown>).get('authenticatorData');
  if(!Buffer.isBuffer(signature)||!Buffer.isBuffer(authData)||authData.length<37)fail('format');
  const nonce=sha256(authData as Buffer,sha256(clientData));
  if(!verify('sha256',nonce,publicKey,signature as Buffer))fail('signature');
  if(!(authData as Buffer).subarray(0,32).equals(this.rpIdHash))fail('app_id');
  const counter=(authData as Buffer).readUInt32BE(33);
  if(counter<=previousCounter)fail('counter');
  return counter;
 }
}

type KeyRecord={publicKey:KeyObject;counter:number;receipt:Buffer;registeredAt:number};
export type SessionClaims={sub:string;scope:'synthetic';exp:number};

/** Challenges, registered installation keys and short-lived scoped session tokens. */
export class InstallationAuth{
 private readonly challenges=new Map<string,number>();
 private readonly keys=new Map<string,KeyRecord>();
 private readonly now:()=>number;
 private readonly newChallenge:()=>string;
 readonly limits={challengeTTL:300_000,sessionTTL:600_000,maxChallenges:1000,maxKeys:10_000};
 constructor(private readonly verifier:AppAttestVerifier,private readonly sessionSecret:string,
  {now=()=>Date.now(),newChallenge=()=>randomBytes(32).toString('base64url')}:{now?:()=>number;newChallenge?:()=>string}={}){
  if(Buffer.byteLength(sessionSecret)<32)fail('session_secret');
  this.now=now;this.newChallenge=newChallenge;
 }
 challenge():{challenge:string;expiresAt:string}{
  const t=this.now();
  for(const [c,exp] of this.challenges)if(exp<=t)this.challenges.delete(c);
  if(this.challenges.size>=this.limits.maxChallenges)fail('challenge_quota');
  const challenge=this.newChallenge();if(!/^[A-Za-z0-9_-]{32,64}$/.test(challenge))fail('challenge');
  this.challenges.set(challenge,t+this.limits.challengeTTL);
  return {challenge,expiresAt:new Date(t+this.limits.challengeTTL).toISOString()};
 }
 private consume(challenge:string){
  const exp=this.challenges.get(challenge);this.challenges.delete(challenge);
  if(exp===undefined||exp<=this.now())fail('challenge');
 }
 /** One-time registration of an attested key. The client attested over SHA256(challenge as UTF-8). */
 register(keyId:string,attestation:string,challenge:string):{status:'registered'}{
  this.consume(challenge);
  if(this.keys.has(keyId))fail('already_registered');
  if(this.keys.size>=this.limits.maxKeys)fail('key_quota');
  const {publicKey,receipt}=this.verifier.verifyAttestation(keyId,Buffer.from(attestation,'base64'),sha256(Buffer.from(challenge,'utf8')),new Date(this.now()));
  this.keys.set(keyId,{publicKey,counter:0,receipt,registeredAt:this.now()});
  return {status:'registered'};
 }
 /** Assertion over clientData = UTF-8 JSON {challenge, keyId, scope}; issues a session token for that scope only. */
 session(keyId:string,assertion:string,clientDataB64:string):{token:string;expiresAt:string;scope:'synthetic'}{
  const record=this.keys.get(keyId);if(!record)fail('unknown_key');
  const clientData=Buffer.from(clientDataB64,'base64');
  const claims=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(clientData)) as {challenge?:unknown;keyId?:unknown;scope?:unknown};
  if(typeof claims.challenge!=='string'||claims.keyId!==keyId||claims.scope!=='synthetic')fail('client_data');
  this.consume(claims.challenge as string);
  record!.counter=this.verifier.verifyAssertion(Buffer.from(assertion,'base64'),clientData,record!.publicKey,record!.counter);
  const exp=this.now()+this.limits.sessionTTL;
  const payload:SessionClaims={sub:'inst-'+sha256(Buffer.from(keyId,'base64')).subarray(0,12).toString('hex'),scope:'synthetic',exp};
  return {token:this.sign(payload),expiresAt:new Date(exp).toISOString(),scope:'synthetic'};
 }
 private sign(claims:SessionClaims){const body=Buffer.from(JSON.stringify(claims)).toString('base64url');return `v1.${body}.${createHmac('sha256',this.sessionSecret).update(body).digest('base64url')}`;}
 /** Returns the installation owner for a valid, unexpired session token, or throws. */
 authorize(header:string|undefined):string{
  if(!header?.startsWith('Bearer v1.'))fail('unauthorized');
  const parts=header!.slice(7).split('.');
  if(parts.length!==3||parts[0]!=='v1'||header!.length>2048)fail('unauthorized');
  const [,body,mac]=parts;if(!body||!mac)fail('unauthorized');
  const expected=createHmac('sha256',this.sessionSecret).update(body!).digest();
  const given=Buffer.from(mac!,'base64url');
  if(given.length!==expected.length||!timingSafeEqual(given,expected))fail('unauthorized');
  const claims=JSON.parse(Buffer.from(body!,'base64url').toString('utf8')) as SessionClaims;
  if(claims.scope!=='synthetic'||typeof claims.exp!=='number'||claims.exp<=this.now()||!/^inst-[0-9a-f]{24}$/.test(claims.sub))fail('unauthorized');
  return claims.sub;
 }
}
