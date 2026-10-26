import {createHmac} from 'node:crypto';
import {expect,it} from 'vitest';
import {AppAttestVerifier,InstallationAuth,decodeCBOR} from '../src/app-attest.js';

it('accepts only the exact signed session shape and rejects expiration',()=>{
 const secret='synthetic-test-secret-never-used-by-a-server';
 const auth=new InstallationAuth(new AppAttestVerifier('ABCDEFGHIJ.org.example.test','development'),secret,{now:()=>1000});
 const sign=(exp:number)=>{
  const body=Buffer.from(JSON.stringify({sub:'inst-'+ '0'.repeat(24),scope:'synthetic',exp})).toString('base64url');
  return `Bearer v1.${body}.${createHmac('sha256',secret).update(body).digest('base64url')}`;
 };
 expect(auth.authorize(sign(2000))).toBe('inst-'+ '0'.repeat(24));
 expect(()=>auth.authorize(sign(2000)+'.extra')).toThrow('unauthorized');
 expect(()=>auth.authorize(sign(1000))).toThrow('unauthorized');
});
it('rejects duplicate CBOR fields rather than interpreting a different last value',()=>{
 expect(()=>decodeCBOR(Buffer.from([0xa2,0x61,0x78,1,0x61,0x78,2]))).toThrow('cbor_duplicate_key');
});
