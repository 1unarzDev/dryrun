# Device checklist (hardware-only checks)

Use a physical iPhone. Install with:
`DEVELOPMENT_TEAM=<TeamID> BUNDLE_ID=com.<you>.dryrun scripts/mac/device.sh`.
Use the fictional sample households only. **Do not send photos, scans, or screenshots of a real home.**
Answer each item with PASS, FAIL (one line describing what happened), or SKIP.

```
Device model / iOS version:            (e.g. iPhone 15 Pro / iOS 26.0)
Has LiDAR (Pro models since 12 Pro)?:  yes / no
Apple Intelligence enabled?:           yes / no / not supported

A. Vault and privacy
A1  Launch, pick "Oak household", force-quit, relaunch → household still there:              
A2  With the app open, lock the phone for 15 s, unlock, return to the app → no
    "could not open" error; data present:                                                    
A3  Settings > Delete all household data → back at onboarding; relaunch → still onboarding:  
A4  App switcher (swipe up and pause) shows the plain "Dry Run" cover, not household data,
    including while the plan PDF preview sheet is open:                                      
A5  Plan tab > Generate plan > Share/Print → preview opens; dismiss; nothing left behind
    (Files app shows no Dry Run PDF unless you saved one):                                   

B. Room scanning (LiDAR phones only; scan ONE room, any room; do not send the scan)
B1  Home > "Scan with RoomPlan" appears (LiDAR) / explanatory message appears (no LiDAR):    
B2  Camera permission asked only when the scan opens:                                        
B3  Scan completes and goes to "Confirm your home"; doors show as needing confirmation:      
B4  Before confirming any door, the fire rehearsal shows "no verified route" (not a route):  
B5  After confirming one exterior door, the fire rehearsal shows a practice route:           
B6  Rough dimension check: scanned room width vs tape measure (meters, e.g. 3.4 vs 3.5):     

C. Display and interaction
C1  2D plan and 3D dollhouse both render; switching is smooth (yes / laggy / broken):        
C2  Settings > Accessibility > Display & Text Size > Larger Text at max: Rehearse and Plan
    screens readable without overlapping text:                                              
C3  VoiceOver on: can start a rehearsal, answer a decision, and open the debrief:            
C4  Tiếng Việt plan: diacritics correct in the app and in the PDF; draft banner visible:      
C5  Print preview (no printer needed) shows all pages with phone numbers as text:            

D. Optional on-device explanations (Apple Intelligence devices only)
D1  Settings in app shows "On-device explanations: Available":                               
D2  Open a preparation card: an extra explanatory sentence appears, or the template only.
    Anything with numbers, medical or safety instructions in the extra sentence = FAIL:      

E. Network
E1  Airplane mode: rehearsals, plan, and help phone numbers all work; Help says current
    conditions are unavailable:                                                              
```
