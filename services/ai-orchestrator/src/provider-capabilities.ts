/** Capability declarations are configuration, not evidence that an account is entitled or a model is useful. */
// Keep extraction quality independent of a cheaper browsing override. Current
// 20B extraction has retained factual/usefulness failures; opt-in evaluation is
// supported, but it must not silently become the production extraction default.
export const defaultGroqExtractorModel='openai/gpt-oss-120b';
export const providerCapabilities={
 gemini:{api:'Interactions',models:['gemini-3.1-flash-lite','gemini-3.8-flash'],privateText:true,applicationFunctions:true,publicResearch:['google_search','url_context'],images:true,retentionControl:'store:false',evaluation:{sixHazards:'director/13 executable 6/6; semantic defects; current prompt requires reevaluation',publicDiscovery:'quota/eligibility failures retained',images:'existing evaluated synthetic role; real-photo/native pending'}},
 groq:{api:'Chat Completions REST',models:['openai/gpt-oss-120b','openai/gpt-oss-20b'],privateText:true,applicationFunctions:true,publicResearch:['browser_search'],images:false,searchAndStrictSchemaTogether:false,strictExtractionRequiresToolsDisabled:true,retentionControl:'deployment-configured; store parameter unsupported',evaluation:{publicDiscovery:'live Denver/Marfa/Albuquerque evidence; fresh useful-option gate open; 20B extraction factual/usefulness failures retained, not quality-qualified; 120B current semantic review pending',privateText:'synthetic adapter tests; current all-six live completion quota/circuit blocked',applicationFunctions:'live preview call succeeded; finalization quota/output failures; no six-hazard pass',images:'unsupported, do not route'}},
} as const;
