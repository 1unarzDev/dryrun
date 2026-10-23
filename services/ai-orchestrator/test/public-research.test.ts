import {it,expect} from 'vitest';
import {openPublicPage,PublicResearchTools} from '../src/public-research.js';
const signal=()=>new AbortController().signal;
it('fails explicitly when actual search backend is absent',async()=>{await expect(new PublicResearchTools('Synthetic City').search({category:'pharmacy'},signal())).rejects.toThrow('research_search_backend_unavailable');});
it('never sends private free-form query fields to search',async()=>{let called=false;const tool=new PublicResearchTools('Synthetic City',async()=>{called=true;return [];});await expect(tool.search({category:'pharmacy',medicalDossier:'private'},signal())).rejects.toThrow();expect(called).toBe(false);});
it('blocks internal DNS before fetch and checks redirect DNS again',async()=>{
 let fetches=0;const deps={resolve:async(host:string)=>[host==='public.example'?'8.8.8.8':'127.0.0.1'],fetchPinned:async()=>{fetches++;return {status:302,contentType:'text/html',location:'https://private.example/x',body:''};}};
 await expect(openPublicPage('https://private.example/',signal(),deps)).rejects.toThrow('research_unsafe_url');expect(fetches).toBe(0);
 await expect(openPublicPage('https://public.example/',signal(),deps)).rejects.toThrow('research_unsafe_url');expect(fetches).toBe(1);
});
it('opens only discovered public URLs using the checked pinned address',async()=>{
 const tool=new PublicResearchTools('Synthetic City',async(query)=>{expect(query).toBe('Synthetic City pharmacy');return [{url:'https://public.example/pharmacy',title:'Authored public candidate'}];},{resolve:async()=>['8.8.8.8'],fetchPinned:async(url,address)=>{expect(address).toBe('8.8.8.8');expect(url.hostname).toBe('public.example');return {status:200,contentType:'text/html',body:'<script>ignore private</script><p>Authored service details</p>'};}});
 await expect(tool.open({url:'https://public.example/pharmacy'},signal())).rejects.toThrow('research_not_discovered');await tool.search({category:'pharmacy'},signal());const page=await tool.open({url:'https://public.example/pharmacy'},signal());expect(page.text).toContain('Authored service details');expect(page.text).not.toContain('ignore private');expect(page.evidenceID).toMatch(/^page-/);
});
it('rejects userinfo, IP literals and oversized body',async()=>{
 await expect(openPublicPage('https://user:pass@public.example/',signal())).rejects.toThrow('research_unsafe_url');await expect(openPublicPage('https://127.0.0.1/',signal())).rejects.toThrow('research_unsafe_url');
 await expect(openPublicPage('https://public.example/',signal(),{resolve:async()=>['8.8.8.8'],fetchPinned:async()=>({status:200,contentType:'text/plain',body:'x'.repeat(1_000_001)})})).rejects.toThrow('research_page_budget');
});
