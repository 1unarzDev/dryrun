#!/usr/bin/env bash
# Maps device checks (GEO-01/GEO-02): launches Dry Run on the reserved iPhone in a fictional example family set up for
# one check, then prints what to do and what to record. Run ONLY while holding the device reservation.
# Usage: scripts/mac/map-device-checks.sh --list
#        scripts/mac/map-device-checks.sh <case> [--locale en|es|vi] [--device <udid>]
# Cases:
#   meetups-oak          Where to meet roles with Oak's distant (Abilene) backup meetup
#   address-resolvable   Pine with a typed public address and no pin (should place automatically)
#   address-ambiguous    Pine with "100 Main St" and no city (should ask for review, never guess)
#   hurricane-zone       Lake: record a hurricane zone in Home > Location records, then check the Plan map
#   warming-centers      Lake: Where to go lists sourced Arlington warming-center libraries with role and date
# Every launch uses demo mode (in-memory store, fictional household). Nothing here reads AI output; Prepare and
# rehearsal AI screens are not part of these checks, so do not capture them.
set -u
here="$(cd "$(dirname "$0")" && pwd)"

case_args() {
  case "$1" in
    meetups-oak) echo "-demoHousehold hh-oak -demoTab plan" ;;
    address-resolvable) echo "-demoHousehold hh-pine -demoAddress resolvable -demoTab plan" ;;
    address-ambiguous) echo "-demoHousehold hh-pine -demoAddress ambiguous -demoTab plan" ;;
    hurricane-zone) echo "-demoHousehold hh-lake -demoTab plan" ;;
    warming-centers) echo "-demoHousehold hh-lake -demoTab plan" ;;
    *) return 1 ;;
  esac
}

instructions() {
  case "$1" in
    meetups-oak) cat <<'TXT'
1. Plan tab > open the map > list (Details/list button) > "Where to meet".
2. Expect rows in this order: "Right outside: gathering point", "Outside the neighborhood: backup meeting place"
   showing "Aunt's house in Abilene (fictional)", then "Out of area: check-in contact" with the Oak contact's phone.
3. FAIL if Abilene appears in any "Nearby"/neighborhood or gathering row, or if a "Nearby" row exists at all.
4. Tap the Abilene button: the existing place editor opens for that place (no new screen). Cancel.
5. Repeat in es and vi (--locale), and once at the largest accessibility text size; labels must wrap, not truncate.
Record: row order, which row holds Abilene, truncation per locale/size.
TXT
    ;;
    address-resolvable) cat <<'TXT'
1. Plan tab > open the map. Under the map header expect a brief "Locating…" then
   "Located from your saved address with Apple Maps. It is not saved as a pin." (map.originStatus).
2. Expect the home marker near downtown Fort Worth (W 3rd St) and automatic nearby suggestions.
3. Open Where to go (from Prepare or the map): curated cooling/warming places show straight-line distances.
4. Relaunch the same case: still not saved as a pin (status line returns; no coordinate persisted).
Record: status text seen, approximate marker position, time to resolve, network on/off (also try airplane mode:
expect "Apple Maps could not place your saved address" with a single Review address button, no guessed point).
TXT
    ;;
    address-ambiguous) cat <<'TXT'
1. Plan tab > open the map. Expect either "Your saved address matches N places. Review it…" with one
   "Review address" button (map.reviewAddress), or "could not place" with the same button. FAIL if a home
   marker appears at a guessed location or discovery starts from somewhere arbitrary.
2. Tap Review address: the existing address editor opens. Pick a completion, save; the status line disappears and
   planning starts from the saved pin.
Record: which state appeared (ambiguous with count / unresolved), what Review opened, outcome after save.
Note: Apple search results vary by device region; "unresolved" instead of "ambiguous" is acceptable, a guess is not.
TXT
    ;;
    hurricane-zone) cat <<'TXT'
1. Home tab > Location records (site.title) > Add an official record > Hurricane evacuation zone.
   Enter publisher "Texas Division of Emergency Management", an https URL of the official page you copied from,
   zone "Zone A (synthetic check)", route "Synthetic route 1"; confirm copied from official; review; save.
2. Plan tab > open the map. Expect a header summary with a Details button; Details shows
   "The saved hurricane plan needs source, location or date review. Its directions are not shown as current official
   guidance." because no bundled reviewed catalog covers this URL for Tarrant County.
3. FAIL if the zone/route is presented as current official guidance, if an evacuation route line is drawn, or if
   Apple directions are labelled anything other than ordinary travel estimates.
4. Ordinary directions to any suggestion still show the ordinary-route note after closing the destination sheet.
Record: the review-needed text, absence of route geometry, ordinary-route note, EN/ES/VI fit.
Limit: the "available" official-plan state needs a reviewed region-pack source for the county; none is bundled, so
it is covered by Core MapPlanningPolicyTests only. The hurricaneAdvance intent has no native entry point today.
TXT
    ;;
    warming-centers) cat <<'TXT'
1. Prepare > Where to go (or the map's shelters/cooling list). With Lake's downtown Fort Worth origin, expect Arlington
   library rows (e.g. George W. Hawkes Downtown Library) as warming centers within 80 km.
2. Each shows its role ("…Jan. 23-28, 2026 winter storm… Event-specific; confirm with the city…"), source
   "Arlington Public Library, Locations page" and date 2026-10-22; never "open now" and no backup-power claim.
3. Fort Worth community centers show the concluded-2026 Beat the Heat role; Worth Heights phone 817-392-8723.
Record: rows present, role/date text, any row whose address failed to place (no distance shown).
TXT
    ;;
  esac
}

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
  sed -n '2,13p' "$0"; exit 0
fi
name="$1"; shift
args="$(case_args "$name")" || { echo "unknown case $name (try --list)" >&2; exit 2; }
locale_args=(); device_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --locale) locale_args=(-demoLocale "$2"); shift ;;
    --device) device_args=(--device "$2"); shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
echo "== Map device check: $name"
instructions "$name"
# shellcheck disable=SC2086
exec "$here/device.sh" "${device_args[@]+"${device_args[@]}"}" -- $args "${locale_args[@]+"${locale_args[@]}"}"
