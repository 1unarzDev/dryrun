import {expect,it} from 'vitest';
import {RequestWindow} from '../src/request-window.js';
it('bounds each installation independently and retires expired windows',()=>{
 let now=0;const window=new RequestWindow(2,100,2,()=>now);
 window.claim('family-a','one');window.claim('family-a','two');
 expect(()=>window.claim('family-a','three')).toThrow('request_quota');
 expect(()=>window.claim('family-a','one')).toThrow('replayed_request');
 expect(()=>window.claim('family-b','one')).not.toThrow();
 expect(()=>window.claim('family-c','one')).toThrow('request_quota');
 now=100;
 expect(()=>window.claim('family-c','one')).not.toThrow();
 expect(()=>window.claim('family-a','fresh-session')).not.toThrow();
});
