import {it,expect} from 'vitest';
import {developmentListenHost} from '../src/listen-config.js';
it('binds only explicit local or synthetic LAN development addresses',()=>{
 expect(developmentListenHost('127.0.0.1')).toBe('127.0.0.1');expect(developmentListenHost('0.0.0.0')).toBe('0.0.0.0');
 expect(()=>developmentListenHost('192.168.1.3')).toThrow();expect(()=>developmentListenHost('example.org')).toThrow();
});
