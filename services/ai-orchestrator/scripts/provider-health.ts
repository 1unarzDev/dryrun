// Development diagnostic: a one-word request per configured model through both SDK paths (Interactions, which the
// gateway uses, and generateContent), to tell provider capacity from app problems. No household data; prints status only.
import {GoogleGenAI} from '@google/genai';
const ai=new GoogleGenAI({apiKey:process.env.GOOGLE_AI_STUDIO_KEY??''});
for(const model of ['gemini-3.1-flash-lite','gemini-3.8-flash']){
 for(const path of ['interactions','generateContent'] as const){
  const started=Date.now();
  try{
   if(path==='interactions')await ai.interactions.create({model,store:false,input:[{type:'user_input',content:[{type:'text',text:'Reply with OK.'}]}],generation_config:{max_output_tokens:5}} as any);
   else await ai.models.generateContent({model,contents:'Reply with OK.',config:{maxOutputTokens:5}});
   console.log(model,path,'ok',Date.now()-started+'ms');
  }catch(error:any){console.log(model,path,'error',error?.status??'',String(error?.message??error).slice(0,120));}
 }
}
