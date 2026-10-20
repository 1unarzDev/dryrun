/** Scheduling is not applying. Before presenting a decision at an event's due
 * minute the director must preview/commit an advance which actually applies it.
 * Future events remain queued; no wall-clock time or household action is implied. */
export function requireAppliedDueEvents(commands:readonly {kind:string;minute?:number}[],initialMinute:number):void {
 let minute=initialMinute;
 const due:number[]=[];
 for(const command of commands){
  if(command.kind==='schedule'&&command.minute!==undefined)due.push(command.minute);
  if(command.kind==='advance'&&command.minute!==undefined){minute=command.minute;for(let i=due.length-1;i>=0;i--)if(due[i]!<=minute)due.splice(i,1);}
 }
 if(due.some(at=>at<=minute))throw new Error('unapplied_due_event');
}

/** Ending a fire exercise cannot stand in for the household's outstanding escape
 * or outside-roster action. Check before preview so finish cannot hide affordances. */
export function requireCompletedFireActions(commands:readonly {kind:string}[],experience?:{hazard:string;feasibleCommands?:readonly {kind:string;target?:string}[];accountedPersonIDs:readonly string[]}) {
 if(experience?.hazard!=='homeFire'||!commands.some(c=>c.kind==='finish'))return;
 const available=experience.feasibleCommands??[];
 if(available.some(c=>c.kind==='escape'))throw new Error('unfinished_fire_escape');
 if(available.some(c=>c.kind==='accountOutside'&&c.target&&!experience.accountedPersonIDs.includes(c.target)))throw new Error('unfinished_fire_accounting');
}

/** These actual departures complete the modeled home boundary. Destination
 * geometry, temperature, services and equipment continuity are not established.
 * This governs new proposals only; the Core reducer still replays old commits. */
export function completedHomeDeparture(experience?:{mechanicsVersion:string;hazard:string;relocated:boolean}):boolean {
 return !!experience&&['dryrun.hazard-mechanics/4','dryrun.hazard-mechanics/5'].includes(experience.mechanicsVersion)&&['flashFlood','freezePowerLoss','heatGridStrain'].includes(experience.hazard)&&experience.relocated;
}
export function requireDepartureDebrief(commands:readonly {kind:string}[],experience?:{mechanicsVersion:string;hazard:string;relocated:boolean}) {
 if(completedHomeDeparture(experience)&&(commands.length!==1||commands[0]?.kind!=='finish'))throw new Error(experience!.hazard==='flashFlood'?'departed_flood_requires_debrief':'departed_thermal_requires_debrief');
}

export function requirePreservedFloodDeparture(initial:{hazard:string;feasibleCommands?:readonly {kind:string}[]}|undefined,preview:{feasibleCommands?:readonly {kind:string}[]}|undefined,hasUserAction:boolean) {
 if(initial?.hazard==='flashFlood'&&!hasUserAction&&initial.feasibleCommands?.some(c=>c.kind==='leaveEarly')&&!(preview??initial).feasibleCommands?.some(c=>c.kind==='leaveEarly'))throw new Error('missed_flood_departure_decision');
}
