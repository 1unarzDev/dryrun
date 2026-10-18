# Owner’s original family-preparedness goal — October 17, 2026

This is the original `/goal` instruction, preserved verbatim below. It is the acceptance brief, not a record
of completion. Current code, documents, tests, adapters, and previous agents’ claims must be reconciled against
these requested outcomes. See CLAUDE_NATIVE_HANDOFF for the owner’s later direction on Claude-led visual
refinement, ideators, friction review, and independent verification.

---

/goal
Continue working in the existing DryRun repository and carry this revision through implementation, integration, and available-platform verification. You already have project context. Treat the current branch as authoritative and reconcile the findings below against it; do not discard newer work. Deliver a focused iOS app that helps a family prepare for emergencies, rehearse decisions in its own home, and keep a clear, shareable plan. Complete the requested product flows, including native RoomPlan capture ready for testing on a LiDAR-capable iPhone Pro. A plan, isolated components, or a prettier demo without connected data flows is not completion.

PRODUCT DIRECTION

DryRun should help a family answer three questions: What should we prepare next? What would we do in our home? Where is our plan when we need it?

Make the core journey: add the household → establish the home and meeting places → practice a short scenario → resolve one concrete preparation gap → share or print the updated plan. Families must get useful preparation tasks and a basic emergency card without scanning, completing every field, or finishing a rehearsal. Preserve a clearly fictional example-home path for immediate exploration.

The differentiator is a coherent connection between the family's actual layout, practical preparations, and a portable plan. Keep the feature set narrow. Prefer short contextual edits, defaults derived from existing information, clear visuals, and ordinary language. Preserve the current calm native design language while improving hierarchy, spacing, navigation, and consistency. Avoid turning the app into a directory, medical-record system, project manager, full CAD editor, or live disaster-command system.

These directions supersede earlier county-first product choices, the equipment-only outage-card scope, and the blanket exclusion of illustrative spatial hazard visuals. Update outdated product documentation accordingly. Preserve conservative routing, evidence provenance, encrypted local storage, and honest descriptions of what a rehearsal can establish.

1. START FROM THE ACTUAL IMPLEMENTATION

The archive has useful foundations. Extend them rather than rebuilding everything:

- RootView currently exposes five tabs: Next, Rehearse, Home, Plan, Help. Household creation and most editing use a seven-step wizard. Next-step questions reopen that wizard at its beginning instead of their relevant field.
- New personal setup already starts with one person named Me, but Person has no relationship/role field. It defaults to an adult in Erath County and attaches the fictional ranch home; Home currently labels that layout as fictional. Preserve and extend this distinction throughout setup, rehearsals, tasks, and exports so example geometry never becomes evidence about the user's actual home.
- HouseholdProfile.privateLocation already has address and coordinates, but the current setup and map flows do not use it. MapKit search, markers, directions, and saved-place storage already exist. The map hides Apple's ordinary POIs, draws no home or saved-place markers, and relies primarily on two geocoded directory entries. This explains its empty appearance.
- Saving a place is available only from some map entry points. PlanBuilder does not accept savedPlaces, so a meeting location can appear in the Plan tab but be absent from the generated PDF. Directions preview only starts from current GPS, despite an adapter capable of other origins.
- The existing outage card is per essential device; families without equipment receive no card. Native PDF preview, ShareLink, and system printing are already implemented; retain and verify them.
- Next steps already evaluates all six scenarios automatically; users do not have to rehearse first. Its real gaps are preparedness coverage, task actions, and completion semantics. Merging and completion use actionID alone, which can collapse two different people's or devices' needs.
- The equipment type and its stored name are separate fields. Default names such as Oxygen concentrator and Portable battery station remain after some type changes. Refrigerated-medication purpose and needsRefrigeration are independent, creating inconsistent simulation semantics. Adding a backup in MedicalSetupView also immediately links it as confirmed compatible before an explicit confirmation.
- The rehearsal floor plan appears only after completion. Earlier and later fire routes are appended to one history and rendered together. Neither home renderer accepts evolving hazard state. Fire origin currently selects every room of a matching kind, rather than one room ID; flood and tornado lack indoor spatial progression.
- The scan importer renumbers the lowest captured floor as level zero; routing treats zero as ground. An upstairs-only or basement-only scan cannot justify that assumption. Rescanning creates a new home ID, and updateHome filters saved places by that ID, potentially discarding meeting places.
- docs/VERIFICATION.md records the October 16 integration pass as 149 core tests, 33 vault tests, 68 backend tests, and Swift syntax parsing on Linux. Those are historical reported results, not verification of this next build. Older simulator results predate the integration. RoomPlanMapping explicitly lists unverified SDK and coordinate assumptions.

Primary implementation entry points, relative to the repository:

Navigation/state: apps/ios/DryRun/App/{RootView,AppModel,DisplayNames,Theme}.swift
Household: apps/ios/DryRun/Home/{HouseholdSetupView,HomeTabView,HomeConfirmationView}.swift
Preparation/card: apps/ios/DryRun/Next/{NextStepsView,MedicalSetupView,OutageCardView,ShareWithFamilyView}.swift
Maps: apps/ios/DryRun/Maps/{MapPlanningView,MapModels,MapKitAdapters}.swift
Spatial UI: apps/ios/DryRun/Spatial/{RoomCaptureContainer,RoomPlanMapping,ManualHomeEditorView,HomeRoomListView,FloorPlanView,DollhouseView}.swift
Rehearsal/plan: apps/ios/DryRun/Rehearse/{RehearseViews,Names}.swift and apps/ios/DryRun/Plan/{PlanViews,PlanPDFRenderer}.swift
Core: packages/DryRunCore/Sources/DryRunCore/{Models,Ranking,Simulation,Spatial,Session,Plan,Content}/
Persistence: packages/DryRunVault/ and apps/ios/DryRun/Services/
Public coverage/content: services/public-api/src/{schema,app}.ts, content/{actions,locales,regions,sources}/

2. MAKE THREE DESTINATIONS FEEL COMPLETE

Consolidate the default navigation to Prepare, Rehearse, and Plan. Preserve useful existing features through these destinations, with settings/language in a toolbar sheet. Introduce no additional top-level feature tab.

PREPARE: Show one prominent recommended action and two smaller priorities, followed by a compact route to all relevant preparations. Include direct Your family and Your home entry points and a consistent Family emergency card shortcut. Give important unresolved items a visible count so limiting the initial list does not conceal them. Recommendations should explain their household relevance in one sentence.

REHEARSE: Present a short scenario choice and the household's home immediately. Keep all six existing hazards available. Make home fire the flagship spatial demonstration, with flood and tornado equally coherent in their own behavior. Use one decision at a time, a visible current scene, and a clear next action.

PLAN: Present a living family card, home escape/shelter diagram, and neighborhood map as visual previews. Contacts and saved destinations belong here. Show available information as it is entered; do not require scenario selection and a Generate button before a basic plan exists. Advanced export choices can be offered when sharing.

Keep a primary task's relevant editor at most one screen transition from a tab root. A sheet may contain the focused form; avoid chains of sheets. Reuse these editors everywhere. Add contact opens Add contact; choose meetup opens place selection; verify exit highlights that opening. Saving the answer returns to the initiating task and updates its status.

Initial personal setup should establish You and invite an optional home address; collect other details progressively. Include Add family member and Finish later. Never make camera access, location permission, an account, a scan, or a complete medical profile prerequisites for basic use. Keep an example-home badge visible through demo rehearsal and export, and require an explicit choice before replacing personal data with an example.

Represent a legitimate household whose home geometry has not yet been added. Update card/plan inputs, snapshot persistence, vault loading, and migrations accordingly; distinguish intentionally absent geometry from corruption. Current guards require a home in important save/card/plan paths. Never satisfy a required HomeModel argument with a fictional personal home; general preparation and the basic card must work with no layout.

3. HOUSEHOLD, MEDICAL NEEDS, AND ADDRESS

Family model and form:

- Start with one identifiable self record. Separate the label You from the person's name and relationship to other household members. Do not infer the user's age or household authority.
- Support optional relationships: mother, father, parent, guardian, child, grandparent, great-grandparent, aunt, uncle, sibling, spouse/partner, caregiver, other household member, and custom. Use inclusive presentation without requiring a conventional family structure.
- Preserve existing assistance, communication, helper, and room-assignment fields. Relationship never implies mobility, medical need, or a duty to enter danger. Distinguish residents from trusted contacts who live elsewhere.
- Add compact, optional person-associated emergency information: critical conditions, severe allergies, essential medication/equipment, communication or mobility needs, and a short user-authored instruction responders should know. Do not build a comprehensive clinical history form. Link devices and assistance needs to the correct person.
- Store emergency contacts structurally with name, relationship, and phone; support international formatting and readable display. A name without a usable phone is an incomplete phone contact. Call actions use the stored number, not regex extraction from prose.

Fix the device and backup editors together:

- The chosen type should supply its localized display name. Offer a separately labeled optional Name or model field. Empty custom names fall back to the type; genuine custom names survive type or language changes. Do not persist English defaults as if they were custom names. Use one shared editor implementation.
- Handle legacy labels carefully: preserve data, recognize known old defaults only where supported, and test migration. Show meaningful labels and selection values without an unexplained second line resembling stale state.
- Separate electrically powered equipment from medicines or supplies needing temperature-controlled storage. Replace Needs to stay cold with an explicit question such as Does this medicine need refrigerated storage? Include Not sure where a fact is unknown.
- Make refrigeration and electrical requirements consistent in the domain model and simulation. They can coexist, but a medicine must not become a directly powered appliance merely because a Boolean was left false. Preserve the recorded original data during migration; uncertain old combinations need clarification, not guessed compatibility.
- Make card sections, missing-information checks, preparation tasks, and completion criteria follow those same support requirements. Cold-storage-only medication must not require a device's electrical backup/runtime. Mixed requirements must track both. Test medication-only and mixed-requirement households so reusing the old card-gap builder does not recreate the bug.
- Keep clinical storage instructions and device backup/runtime information user- or provider-supplied. Offer a concise prompt to check labeling, the pharmacist, clinician, or manufacturer when information is missing. Do not generate storage limits, treatment changes, or patient-safe interruption windows. FDA guidance supports keeping medical details current and following medicine/device-specific instructions [6, 7].
- Adding a battery or generator does not confirm compatibility, safe setup, sufficient output, or operating duration. Distinguish ownership, assignment, compatibility, and confirmed setup. Ask only the relevant questions; leave advanced technical details optional when unknown.
- Preserve editable drafts on failed saves. MedicalSetupView must check whether updateHousehold succeeded before dismissing. Use transactional save behavior for completion records and plans as well.

Replace county entry with address-led location:

- Use address autocomplete through an iOS-18-compatible MapKit/Core Location adapter. Resolve a selected address, show its pin for a simple confirmation/correction, and keep apartment/unit details separate. Derive city, administrative area, postal code, and country where available. Allow manual text or a dropped pin, with unknown derived fields preserved [9].
- An address is optional. No GPS permission is required to plan from a typed address. Request current location only when that control is chosen. Address search and nearby discovery use Apple services; explain this once at the relevant step without repeated permission-like interruptions.
- Establish one canonical home location and a stable home identity. Preserve existing IDs and references on a rescan of the same home; distinguish that operation from moving to a new address. Address corrections should invalidate affected map results and plans without resetting the family.
- Administrative areas are derived metadata and optional resource-coverage inputs. An Apple county name is not automatically a trusted region ID or FIPS code. Decouple general household planning from the optional supported-region contract. Keep the public backend restricted to supported, allowlisted coverage unless adding a provider is independently justified. An unsupported home uses local planning and Apple search without a public-region request or a substituted Texas region; retain existing Texas resources as optional content.
- The core works outside Texas and outside the US. Adapt units, addresses, and phone presentation. Show official alerts, service numbers, and resource status only for explicitly supported coverage. Never assign Texas contacts or 911 to an unknown foreign location. A simple country-aware, source-verified emergency-contact mechanism and honest unsupported state are sufficient; a global alert backend is outside scope.

4. REPLACE THE OUTAGE CARD WITH A FAMILY EMERGENCY CARD

Every household gets a useful card, including households with no powered equipment or scan. Create a household-level emergency document; retain the existing device-continuity detail as optional supporting content.

Use this visual hierarchy:

1. Household identity/address and a clearly prominent Critical information section, associated with specific people. Show the family-selected information a responder needs to find quickly: serious allergies/conditions, essential equipment, communication/access needs, and brief recorded instructions.
2. Primary emergency contacts, with relationship and readable phone numbers. Include an out-of-area contact where supplied.
3. Outside meeting location near home and a backup location outside the neighborhood, each with name, address or landmark, and concise finding instructions. The Red Cross recommends these two distinct meetup purposes [2].
4. Additional relevant medical continuity, transport, caregiver, and essential-supply details.
5. Last reviewed date, plus clear missing-information states. An empty medical field means not provided, not no medical conditions.

Give users direct control over which sensitive fields go into an export. Show the actual selected-content preview before sharing. Include the critical information by intentional selection; never hide it unpredictably behind a generic private-notes toggle. Keep the core card concise and legible, with continuation pages for necessary detail instead of tiny text or clipped notes.

Reuse native PDF preview, the Apple share sheet, and system Print. Produce a readable phone view and a printable Letter/A4 document. The recipient must be able to use the PDF without installing DryRun or having an account. Show all essential contact and meetup details as text even when images or links are unavailable. A QR code, wallet pass, or lock-screen extension is not a release requirement.

The card must stay current after edits and open offline. Share and print the same underlying content shown in its preview. Preserve protected temporary-export handling and test the share-sheet lifecycle so files remain available until the activity finishes, then are cleaned up. Do not upload medical data, contacts, or home geometry to the public service.

5. PREPARE MUST COVER PREVENTION, MITIGATION, AND READINESS

Introduce a baseline preparedness evaluator using household/home facts, then merge applicable rehearsal-derived gaps. Keep the existing deterministic recommendation engine and useful counterfactual comparison. Do not make a rehearsal result the only way a missing real-world preparation can be recognized.

Build a coverage matrix connecting each preparation to its input facts, applicability, priority, completion criteria, direct editor, relevant scenario, and authoritative source. Cover at least:

- Fire: smoke and CO alarm presence/location and relevant checks; a fire extinguisher and its accessible location; family awareness of that location; clear doors/windows; possible second ways out; an outside meetup; help needed by occupants. Extinguisher preparation must not teach children or untrained users to remain inside or fight a spreading fire. Route/supply guidance needs appropriately sourced wording [3, 14].
- Basic continuity: stored drinking water, shelf-stable food, dietary/infant needs, first aid, flashlight, batteries or power bank, radio/alerts where relevant, sanitation, and pet essentials. Keep this a short applicable checklist rather than a shopping catalog. Distinguish having supplies from knowing where they are. Use the existing CDC-based water storage target with units and household count; label it a storage planning target, not a clinical drinking prescription [4, 14].
- Family coordination: near-home and backup meeting places; trusted and out-of-area contacts; selected critical card details; helpers/caregivers; transportation or a no-car plan; a way to reconnect when separated [2].
- Medical continuity: device-specific backup checks, equipment supplies, medication availability and storage planning, and relevant provider/distributor contacts [6, 7].
- Hazard-specific mitigation: chosen tornado shelter, local-alert setup where supported, cold/heat preparations, and flood preparations appropriate to the home and official guidance. Model household needs and resources without pretending to forecast a disaster at the address.
- Maintenance: review a stale card/contact, recheck supplies or alarms, and revisit an escape plan after the home changes. Offer reminders only by explicit user choice; no default notification campaign.

Keep alarm presence/location, applicable coverage, and a user-recorded functional check as separate facts. The current fire rules accept a verified alarm annotation; confirming a marker must not certify a successful test or whole-home coverage. Generate the relevant missing-check tasks, and place known missing essential protection in the highest applicable life-safety priority band.

Use one documented deterministic order across per-scenario ranking and the merged list. A sensible starting order is: known essential medical/access/escape gaps; unresolved facts needed for a relevant safety-critical plan; core supplies/communication/meeting preparations; other applicable mitigation; maintenance and further practice. Refine with sourced reasoning. Within a tier, prefer household relevance, dependencies, practical effort/cost, and benefit across hazards, with stable tie-breaks. An easy task must not outrank a critical dependency solely because it is easy. Irrelevant unknown fields must not crowd the list.

Make real preparation the primary action: Add contact, Choose meeting place, Check exit, Record supply location, or Confirm backup. Keep Try this change secondary. Complete factual tasks automatically when their actual required records are saved; physical checks still need an explicit user record. A generic Done button must not certify device compatibility or route suitability.

Fix task identity: action + affected person/device/room/place, or an explicit aggregate with individually tracked subitems. Completing one concentrator's backup must not complete another person's ventilator backup. Preserve subject context across merges, labels, comparisons, and completion. Add Undo/reopen and invalidate only the relevant completion when its underlying facts change. Migrate legacy action-only completion cautiously; do not silently assign it to every matching new instance.

Keep confidence and completion distinct. A hypothetical rehearsal choice never edits actual household facts. A completed checklist never becomes a percentage claiming a family is safe. Summarize tangible progress such as an established meetup or a checked backup.

6. BUILD A USEFUL MAP AROUND THE HOME

Finish the existing MapKit integration as one shared planning flow reachable from Plan, the home editor, and a related preparation task.

- Immediately show the confirmed home, both saved meetup locations, and other selected resources as distinct, persistent annotations. Support text-only places and arbitrary dropped pins such as a driveway or landmark. Let users edit the label, purpose, and finding instructions. Keep selection and sheet state separate from persistent markers.
- After the user confirms an address, automatically start one bounded nearby lookup with visible progress and cancellation. Permit disabling or retrying discovery; do not require category-by-category setup before useful suggestions appear. Default categories: hospitals/medical help, pharmacies, and groceries/food-water supplies. Put additional preparedness supplies and officially sourced community resources behind a lightweight More control. Return a few useful candidates per category, deduplicate them, preserve results on sheet dismissal, and support Search this area and radius expansion for rural areas.
- Treat automatically discovered places as suggestions. Saving a hospital or shop does not make it the family meeting place. Retain provenance, source IDs where present, and check dates. Distinguish an emergency department from an ordinary medical practice only where supported by the data; do not claim the nearest result is the nearest usable emergency facility.
- A shop marker does not establish stock or opening during a disaster. A public office or school is not an activated shelter. Official shelters/cooling/warming sites need an appropriate authoritative source and a clear current-status state. Respect these distinctions without stacking repetitive warnings on every card.
- Keep the map and list equivalent: category, name, address, distance, and save/contact/directions actions. Make empty, offline, permission-denied, service-error, and unsupported-coverage states useful and different. Do not show No verified pins merely because the old county directory is empty when other results are visible.
- Default directions origin to the saved home; offer current location or another saved place. Keep travel mode selection in the destination sheet. Fit the origin, destination, and full path; present distance and time with the correct mode and units. Handle unsupported transit or unavailable routes honestly. Ordinary Apple directions are planning aids, not verified disaster-safe or wheelchair-accessible evacuation routes.
- Reuse and extend the existing plain-value search/directions adapters. Add cancellation/stale-result tests, with independent request state for parallel category lookups so a shared service's cancel-previous behavior does not cancel the other categories. Never allow an old address or region response to overwrite the current view.
- Address/search inputs may go to Apple for the requested operation. Family details, medical records, contact names, and indoor scans must stay out of DryRun's public API, diagnostics, and model requests.

Offline essentials are saved place names/addresses/coordinates, contacts, the home diagram, and the retained plan. Do not promise live Apple search, fresh alerts, routing, or arbitrary map tiles offline. Check the applicable Apple snapshot/export terms and preserve required attribution before retaining map imagery [9, 10].

7. FINISH ROOMPLAN AND MAKE HOME CORRECTION INTUITIVE

Implement against the actual installed SDK and iOS 18 deployment target, using availability checks where needed. RoomPlan is a native capture capability; a mock result is insufficient. Use its support check independently from network, location, or Apple Intelligence availability [8, 15].

Capture flow: brief scan guidance → capture a room → continue connected rooms in a valid shared frame → process the structure → inspect the clean home preview → answer the few critical confirmations → save. Use Apple's supported shared-session/StructureBuilder approach for merged rooms and verify current multi-floor capabilities rather than guessing from old assumptions [8, 16].

- Verify RoomPlanMapping's surface categories, parent identifiers, floor polygons, local/world transforms, scale, orientation, and story handling against the real SDK. Compare a consenting physical test space to measurements when a device is available. Keep a raw/proposed representation and explicit provenance.
- Use originating capture/session generation identifiers to reject late callbacks after cancellation, retry, a new capture, repeated Finish, or background interruption. A guard that only checks mutable current controller state is insufficient without proof. Preserve valid completed scan groups while rejecting merges across unrelated coordinate frames. Handle processing failure with a useful retry or retained draft.
- Distinguish captured floor index from actual floor identity, elevation, and exterior grade. Ask whether a level is ground, above, or below, and confirm exterior discharge where needed. Never infer ground level merely from the lowest scanned story. Handle walkout basements and split levels explicitly. Confirm stair endpoints and landings; avoid linking the first vertically overlapping room automatically.
- Keep a stable identity for a rescan of this home. Preserve address, geographic meeting places, and unaffected records. Remap rooms/people/annotations only with evidence; surface ambiguous assignments briefly. Moving home is a separate operation with an explicit preservation/reset decision.
- Unsupported hardware, denied camera, incomplete capture, or loss of tracking must leave manual and example-home paths usable. Never silently replace a failed personal scan with fictional geometry.

Replace the current large form/list with a shared 2D home canvas and compact contextual editing sheet:

- Tap a room, doorway, window, stair, obstacle, or annotation to highlight exactly that item. Match the visual highlight to the question. Offer clear room names/types/floors; constrained move/resize/correction controls; add/remove room; doorway/exterior classification; opening width/operability where relevant; stair endpoints; and equipment/shelter locations. Keep advanced geometry out of the ordinary path.
- Provide Undo, explicit Save, retained drafts, and Finish later. Use confirmation for destructive replacement/deletion, not a modal after every harmless tap. Preserve already entered width/operability when adding an opening's missing connection. Reset contextual form state when selecting another item.
- Use one confirmation and validation service across manual and scanned edits. Prioritize facts needed for the route or shelter the user is working on. Differentiate reviewable geometry, confirmed facts, remaining unknowns, and actual completeness; never show Everything is done while the validator still reports critical unresolved issues.
- Separate window inventory from an emergency escape option. Finding or confirming a window does not establish suitable exterior access or the relevant person's ability to use it. Enforce necessary egress/mobility suitability as a routing requirement, not a footnote on an otherwise valid-looking route. Do not invent a second exit to satisfy a checklist.
- Identify apartment/common-building routes separately from the unit, and expose missing common stairs or exits honestly. A unit scan cannot certify the full building's evacuation plan.

Keep one canonical home model for 2D, 3D, routing, and export. Reconcile current differences: the dollhouse omits obstacles/stairs and draws walls through openings. Render meaningful doorway gaps, stairs, windows, and obstacles accurately. Prefer a legible top-down view as the default; optional 3D should make the same layout easier to understand. Reuse simplified geometry and cache static meshes; hazard animation should not rebuild the entire scene every frame.

8. MAKE SPATIAL REHEARSAL THE FLAGSHIP EXPERIENCE

Create a shared, deterministic spatial state for each exercise stage: scenario/seed, selected origin, affected rooms/openings/floors, occupants and starting locations, chosen shelter/destination, and each person's current route/status. The current rehearsal cursor, route guidance, 2D scene, 3D scene, text, and comparison view must read that same state.

Extend the exterior-focused route contract with explicit purposes/destinations for outdoor egress, a household-confirmed interior shelter, and a scenario-specific refuge. Reuse geometry, portal, and mobility validation; do not calculate an exterior exit route and relabel it as a shelter path. Test each destination type, including unconfirmed/inaccessible destinations and stairs excluded by mobility needs.

Keep historical routes as history. A route superseded by smoke, blockage, or another authored event must not continue to look available. Present one selected person's route clearly, with an easy family/person selector where necessary. Preserve explicit unknown start and no-supported-route results. Support daytime starting rooms through a small optional override instead of always using sleeping assignments.

Show the home at the beginning. Use a concise prompt, a visible consequence, and the next decision. Allow pause/replay or review of earlier stages, but never present exercise time as a prediction of remaining safe time. End with the most useful preparedness action, opened directly in context. Reuse the existing before/after comparison to explain one change without marking that hypothetical change as completed.

FIRE

- Select one actual origin by room ID, including kitchen, bedroom, hallway, stairs/landing, or a location near an exit. Room kind can propose a default but cannot mark every kitchen as simultaneously burning. Correct the malformed fire-origin fact-key interpolation while touching this path.
- Introduce visible staged fire/smoke spread using authored, topology-aware exercise rules. The state should clearly explain which room or connection became unavailable and why the route changed. Coherent room/door relationships drive progression; visual effects never determine route validity.
- Show current affected areas, the person's location, confirmed usable exit routes, and the outside meetup. Support primary-exit blockage, an independent alternate when one exists, and clear outcomes when all supported paths are unavailable. Never fabricate a route through a wall, excluded room, unsuitable window, unverified shared stair, or a helper's re-entry.
- Correct the existing removal of a person's start room from blockedSpaceIDs before routing. Starting inside an affected area must retain that exposure in the shared state. A supported departure from that area needs an explicit authored start-state rule, distinct from permitting travel through it; otherwise show the supported exposed/trapped/unknown outcome. Never erase a hazard merely to make a route appear.

FLOOD

- Add an indoor-flood exercise with explicitly selected water-entry/affected areas and known floor relationships. Show staged water occupying the relevant lower spaces and changes in accessible connections. Low room/floor status comes from confirmed geometry or an exercise assumption, not address geocoding or visual guesswork.
- Distinguish a local household leak from a broader flood/evacuation scenario. Use guidance appropriate to the chosen scenario. For regional flooding, teach early action and official instructions; do not make Go upstairs the universal first response. If an authored trapped case requires higher refuge, avoid routes through water, flooded electrical areas, or a closed attic, and handle homes with no supported refuge [5].
- Preserve the existing road/water-safety guidance and no-car considerations. No map route may be advertised as flood-safe because ordinary directions exist.

TORNADO

- Highlight the household-confirmed shelter candidate and a supported path to it, using explicit floor/access information. Show why the chosen location reduces window/exterior exposure, without calling it an engineered safe room.
- Include restrained window-impact/shattering cues and exposure highlighting that teach the reason for moving away from windows. Give users an equivalent static scene under Reduce Motion. The visualization must never imply that opening windows helps.
- Handle manufactured homes, apartments, upper floors, mobility constraints, and unavailable shelter paths with appropriate planning outcomes; do not certify an unsuitable building from its scan. Nearby shelter selection is a preparation decision, not an automatically prescribed drive during a warning [11].

Implement these as illustrative educational scenarios with explicit assumptions, not validated fire dynamics, hydraulic forecasts, structural-breakage predictions, or real-time emergency navigation. Use a compact persistent Exercise label and concise contextual uncertainty where it affects a choice. Avoid repeated obstructive disclaimers. Never emit survival scores, injury probabilities, medical deadlines, or an apparently precise safe escape countdown. Safety-relevant wording must remain sourced and honestly reviewed; a language model may not decide routes or clinical instructions.

The existing example floor plan is the first demonstration fixture, not the acceptance boundary. All three spatial hazards must work across the configurations in section 11, including informative incomplete/no-route states.

9. GENERATE ONE COHERENT VISUAL PLAN

Extend PlanDocument/PlanBuilder into a shared snapshot that includes the emergency card, canonical home/route data, selected saved places, map-rendering inputs, source/review metadata, and household/home/place revisions. Keep MapKit and UI frameworks out of DryRunCore by using plain structures and app-layer render adapters.

Build these coordinated visual sections:

- Family emergency card with prominent selected critical details.
- Neighborhood map with the home, primary and backup meetup, and a small number of family-selected preparedness resources. Use numbered symbols with matching text details. If an out-of-area place would make the neighborhood unreadable, give it a second extent/inset or a clearly separate panel.
- Clean home diagram for each relevant floor showing room labels, confirmed exits, applicable primary/alternative paths, shelter location, and useful supply/equipment annotations. Use exact route-leg geometry, not a new interpretation made for export. Label the scenario/person or baseline assumptions for each route; do not combine incompatible fire/flood/tornado directions into one unqualified path.
- Short, prioritized instructions and contacts with readable source/review dates.

Indoor metres and geographic coordinates are different systems. Display the neighborhood map and home diagram as separate coordinated panels unless actual georeferencing exists. Do not paste an unaligned indoor plan onto satellite imagery.

For Apple map exports, verify the supported snapshot API and attribution rules. MKMapSnapshotter does not automatically capture the app's annotations/overlays: draw the intended markers/paths at snapshot coordinates as appropriate [10]. A snapshot failure must still yield a useful text-and-home-diagram plan with a truthful map state. Do not make an unavailable map stall the family card.

Saving a meeting location must update every related view and the next PDF. Unify or explicitly link the indoor outside-meetup annotation and the geographic meeting-place record so one does not falsely report the other as missing. Fix save-before-publish behavior for generated plans. Manage async generation, revision invalidation, and last known saved output so a late task cannot overwrite newer edits.

Render and inspect phone previews and exported PDFs, including very long individual notes. Split oversized blocks across pages instead of relying on the existing first-block exception. Verify every vital detail remains readable in grayscale, Letter/A4, large families, long addresses, Spanish/Vietnamese, and map-unavailable cases. Never solve overflow by shrinking the whole card excessively.

10. FINISH LOCALIZATION AND ACCESSIBILITY BEFORE EXPANDING LANGUAGES

English remains the canonical authored content. The current JSON locale packs are not an automatic whole-app translation system, and DisplayNames/Names plus many views contain English-only values. Fix the existing English, Spanish, and Vietnamese experience end to end: tabs, picker labels and selected values, placeholders, relationship/device types, errors, map controls, scan coaching supplied by the app, room editing, confirmation, units/plurals, accessibility labels, and exports.

Use stable model IDs with localized display strings. Preserve proper names and user-entered medical notes. Avoid duplicating translation systems unnecessarily; choose a maintainable bridge between existing versioned content packs and native UI localization. Derive language choices from available complete packs, with clearly identified fallback where content is missing.

Investigate additional languages only after this works. Apple's Translation framework provides text translation and language availability/download checks; it is not a switch that automatically localizes all controls [12, 13]. If compatible, reliable optional translation of noncritical content is low effort, implement it with supported-language checks and clear fallback. Core emergency content and PDFs must work without a just-in-time language download. Never silently replace medical instructions, doses, addresses, or user-authored critical notes with unreviewed generated translations. Extra languages are conditional scope and must not delay complete core flows.

Audit VoiceOver order, non-color status cues, large Dynamic Type, small screens, light/dark mode, contrast, and Reduce Motion. Every map and home interaction needs an understandable text/list alternative. Give image/route summaries meaningful labels. Test the actual forms and exports; translated headings alone do not count as localization completion.

11. VERIFICATION THAT MATCHES THE REAL RISKS

Use parallel agents for independently owned core/preparation, maps/plan, and scan/rehearsal work, with explicit ownership of shared models and AppModel. Integrate often. Have an independent reviewer inspect safety semantics, navigation friction, and screenshots; turn concrete findings into fixes. Avoid parallel changes that silently conflict in contracts or persistence.

Add meaningful tests for the new behavior. Reuse existing suites and fixtures; do not inflate counts with tests that merely mirror implementation. Start by reproducing the reported selector, missing-map, missing-PDF-meetup, and stale-route problems on an available simulator.

Mandatory behavioral gates:

A. DATA AND PREPARATION

- Old vaults decode/migrate without resetting households, custom labels, contacts, saved places, or home links. New required fields have a tested migration/default policy.
- One-self setup, additional relationships, unknown age/location, and explicit fictional-demo handling work.
- A personal household with intentionally absent home geometry saves, reloads, receives general preparations, and opens its basic card without a fabricated home; corruption still produces its distinct recovery state.
- Fresh install: skip address and scanning → add a contact → view/share the family card → relaunch → verify persistence. Spatial guidance stays explicitly unavailable until an appropriate layout is supplied and reviewed.
- Device/backup switching works in every entry point; custom labels survive. Refrigeration and power dependencies agree with stored inputs; adding a backup never confirms compatibility.
- Two devices/people/rooms can have independent same-type tasks. Completion/Undo persists, factual edits update the right task, and failed writes do not show success.
- A family without any medical equipment can create, view, share, and print its emergency card.

B. ADDRESS, MAP, AND PLAN

- Test a Texas address, an address elsewhere in the US, a non-US address, a rural address, and skipped/unresolved address. No forced county, inaccurate Texas fallback, or default foreign 911.
- Deny GPS and still search around the saved home and plan ordinary directions where services are available. Test rapid address/category changes, empty results, outage, and late responses.
- Home and saved meeting places remain visible after sheets close and after relaunch. Saving/editing/removing a place works from every entry point and changes the generated document consistently.
- Test map-snapshot failure, unavailable tiles, offline reopening, and selected-content exports. Preserve structured international phone values. Verify no private household fields cross the public-service boundary.
- A rescan of the same home preserves geographic plans and prompts only for room associations that genuinely need remapping.

C. SPATIAL CORRECTNESS
Extend the existing ranch, apartment, and two-storey fixtures with: studio/open-plan; concave/L-shaped layout; basement and walkout; split level; upper-floor apartment/shared corridor; missing room/incomplete scan; ambiguous or duplicate opening; obstructed/narrow doorway; offset stair landings; and households needing mobility/assistance accommodations. Reuse fixtures for overlapping cases rather than creating a combinatorial maintenance burden.

For fire, enumerate valid origin rooms and representative resident starts, including near each exit, a hallway, bedroom, kitchen, and stair/landing. Include blocked primary, no independent alternative, and all-exits-blocked conditions. For flood, vary affected low spaces, floor relationships, and access to higher refuge. For tornado, vary the available interior shelter, windows/exterior exposure, building type, and reachable floors.

Assert deterministic states for a recorded seed, no routes through excluded space or walls, no unsupported window/exterior-grade shortcuts, no teleportation between floors, legal portal transitions, correct subject/stage association, correct incomplete/no-route explanations, and 2D/3D/export agreement. A previous route must disappear or be clearly historical once invalidated. Visual hazard states must agree with routing exclusions. Do not claim these fixtures prove all houses are safe.

D. NATIVE BUILD AND DEVICE READINESS

- Run the core/vault/backend tests and current app build with the actual SDK/deployment target. Existing scripts include scripts/swift.sh, scripts/mac/verify.sh, scripts/mac/screens.sh, and scripts/mac/device.sh. Use an authorized available Mac workflow; Linux swiftc -parse is syntax checking only.
- On the simulator, verify the full address → home/map → meetup → preparation → spatial rehearsal → updated plan → share/print journey. Capture new screenshots or recordings for the changed screens; old screenshot tours are not proof of this revision.
- On a supported physical iPhone Pro when available, scan connected rooms, process the structure, correct a room/opening, confirm an exit/floor, assign an occupant, save/relaunch, rehearse, and export. Also test interruption, cancellation/restart with late callbacks, repeated Finish, denial, poor capture, and unsupported hardware/manual fallback.
- Record device model, OS, build/commit, exact tested paths, observed errors, and unresolved limitations. Keep private real-home scans local; use fictional/anonymized geometry in shareable evidence.
- If physical hardware is unavailable, complete implementation and the current native iOS build, then prepare precise installation steps and a short physical-test checklist. Use Ready for iPhone testing only after the target compiles successfully and a concrete installation path exists. Without a Mac/native build, finish portable work and report Implementation prepared; native build and device test pending. Do not label scanning Device verified or the release fully verified without the corresponding evidence; syntax parsing does not prove SDK compatibility.

E. USABILITY AND PRESENTATION
Target first useful preparation/basic card in roughly 90 seconds or less without a scan, important editors in one transition from the tab root, and a default rehearsal of roughly two to four minutes. These are design/test targets, not claims until measured. Review a small phone, accessibility text, VoiceOver, Reduce Motion, each supported language, and PDFs. Correct confusing item highlights, hidden primary actions, label collisions, and selection loops.

12. IMPLEMENT IN THIS ORDER, THEN PREPARE A CONVINCING DEMONSTRATION

Phase 1 — Reliability and shared data: reproduce current bugs; settle household/location/emergency-profile/task/plan/spatial-state contracts, including a household with no home geometry; migrate safely; fix transactional persistence, task subjects, backup semantics, floor/grade correctness, and stale routes. Compile native adapters early so SDK problems are discovered before polishing dependent UI.

Phase 2 — Complete the product: consolidate navigation; ship direct household editors, the family card, broad prioritized preparations, home-centered maps and meeting selection, visual plan/export, and a complete RoomPlan correction path. Complete supported-language strings alongside these changes.

Phase 3 — Deliver the flagship: integrate fire/flood/tornado visual rehearsals with the same canonical state; test multiple configurations; finish native/device checks and independent visual/usability review. Capture the working journey and update docs. Extra languages, richer visual effects, or optional reminders come after required behavior, not instead of it.

Add only a few lightweight refinements that reinforce the main journey:

- Close the preparation loop automatically when a needed contact/place/fact is saved.
- Add one brief family-check question after a rehearsal, such as Where will we meet? or Who helps this person?, with optional We reviewed this together. No family accounts or invitations are needed.
- Show when key information was reviewed and allow a user-chosen reminder. Do not require reminders to use the app.
- Preserve explicit, understandable before/after explanations of one preparation using the existing comparison engine. This can show the technical value of DryRun without a numerical safety score.

For community impact, prepare a short usability protocol and a local, privacy-minimal results template. When consenting testers are actually available, observe several unfamiliar households completing tasks without coaching, including a household with an accessibility/medical need if possible. Measure time to a useful plan, navigation errors/abandonment, ability to identify the meeting place and appropriate route/shelter, and completion of one practical preparation. A small pilot is usability evidence, not proof of reduced injuries. Never invent participants, feedback, partner review, outcomes, or professional endorsement. Prepare outreach materials if useful; do not send messages or recruit people without explicit authorization.

FINAL DELIVERABLES

Deliver integrated source changes and migrations, the updated working app, complete supported-language content, focused tests/fixtures, visually checked card/full-plan examples using fictional data, and exact build/device installation instructions. Update ARCHITECTURE, UI_AUDIT, MAPKIT_SCAN_INTEGRATION, SAFETY_AND_CONTENT, VERIFICATION, DEVICE_CHECKLIST, DEMO_SCRIPT, and AI_ASSISTANCE only to reflect the resulting implementation and actual evidence.

Finish with a compact requirement-to-evidence table: requested change, implemented behavior, files, validation performed, remaining hardware/human check. Explain material remaining limitations explicitly. Do not stop at a plan, leave required screens as placeholders, declare a feature complete because its adapter exists, or claim tests you could not run. Ask only for a real blocker that cannot be resolved with current access after completing unaffected work. Do not publish, submit the competition entry, or contact third parties without the user's explicit authorization.

AUTHORITATIVE REFERENCES
Checked October 17, 2026. These support platform facts and content constraints; they do not validate DryRun's implementation. Recheck relevant SDK availability and safety wording when implementing. Existing source IDs/content-review status should be updated consistently.

[1] Congressional App Challenge — 2026 official rulebook:
[https://www.congressionalappchallenge.us/wp-content/uploads/2026/05/2026-CAC-Rules.pdf](https://www.congressionalappchallenge.us/wp-content/uploads/2026/05/2026-CAC-Rules.pdf)

[2] American Red Cross — Make a plan (meeting places, contacts, family coordination):
[https://www.redcross.org/get-help/how-to-prepare-for-emergencies/make-a-plan.html](https://www.redcross.org/get-help/how-to-prepare-for-emergencies/make-a-plan.html)

[3] US Fire Administration — Home fire escape plans:
[https://www.usfa.fema.gov/prevention/home-fires/prepare-for-fire/home-fire-escape-plans/index.html](https://www.usfa.fema.gov/prevention/home-fires/prepare-for-fire/home-fire-escape-plans/index.html)

[4] CDC — Create and store an emergency water supply:
[https://www.cdc.gov/water-emergency/about/how-to-create-and-store-an-emergency-water-supply.html](https://www.cdc.gov/water-emergency/about/how-to-create-and-store-an-emergency-water-supply.html)

[5] National Weather Service — During a flood; flood safety and closed-attic precautions:
[https://www.weather.gov/safety/flood-during](https://www.weather.gov/safety/flood-during)
[https://www.weather.gov/pah/FloodSafetyWeek](https://www.weather.gov/pah/FloodSafetyWeek)

[6] FDA — Safe drug use after a natural disaster:
[https://www.fda.gov/drugs/emergency-preparedness-drugs/safe-drug-use-after-natural-disaster](https://www.fda.gov/drugs/emergency-preparedness-drugs/safe-drug-use-after-natural-disaster)

[7] FDA — Medical devices and natural disasters:
[https://www.fda.gov/medical-devices/emergency-situations-medical-devices/fda-offers-tips-about-medical-devices-and-natural-disasters](https://www.fda.gov/medical-devices/emergency-situations-medical-devices/fda-offers-tips-about-medical-devices-and-natural-disasters)

[8] Apple — Explore enhancements to RoomPlan (shared session and StructureBuilder):
[https://developer.apple.com/videos/play/wwdc2023/10192/](https://developer.apple.com/videos/play/wwdc2023/10192/)

[9] Apple — Address completion and nearby points of interest:
[https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter](https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter)
[https://developer.apple.com/documentation/mapkit/interacting-with-nearby-points-of-interest](https://developer.apple.com/documentation/mapkit/interacting-with-nearby-points-of-interest)

[10] Apple — MKMapSnapshotter:
[https://developer.apple.com/documentation/mapkit/mkmapsnapshotter](https://developer.apple.com/documentation/mapkit/mkmapsnapshotter)

[11] National Weather Service — Tornado safety:
[https://www.weather.gov/safety/tornado-during](https://www.weather.gov/safety/tornado-during)
[https://www.weather.gov/ctp/TornadoSafety](https://www.weather.gov/ctp/TornadoSafety)

[12] Apple — Translation:
[https://developer.apple.com/documentation/translation/](https://developer.apple.com/documentation/translation/)

[13] Apple — Translation language availability:
[https://developer.apple.com/documentation/translation/languageavailability](https://developer.apple.com/documentation/translation/languageavailability)

[14] American Red Cross — Home fire preparedness and emergency-kit basics:
[https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/fire/home-fire-preparedness.html](https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/fire/home-fire-preparedness.html)
[https://www.redcross.org/local/nevada/about-us/news-and-events/press-releases/preparednessmonth2026snv.html](https://www.redcross.org/local/nevada/about-us/news-and-events/press-releases/preparednessmonth2026snv.html)

[15] Apple — RoomCaptureSession capability check:
[https://developer.apple.com/documentation/roomplan/roomcapturesession/issupported](https://developer.apple.com/documentation/roomplan/roomcapturesession/issupported)

[16] Apple — Scanning rooms of a structure (current documentation, including floor relationships):
[https://developer.apple.com/documentation/roomplan/scanning-the-rooms-of-a-single-structure](https://developer.apple.com/documentation/roomplan/scanning-the-rooms-of-a-single-structure)
