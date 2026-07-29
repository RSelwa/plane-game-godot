class_name CockpitFacts
extends RefCounted

## THE FACT CATALOG — the edgework the pilot reads aloud to the tower.
##
## Facts are declared here ONCE and referenced by name from module files. A round does
## NOT generate this whole catalog: ModuleRegistry.build_manual_data() collects the UNION
## of the facts required by the mission's modules, so a two-module mission rolls only the
## facts those two modules actually read. Unused facts would be free red herrings, and a
## red herring should be a deliberate mission choice, not an accident of the catalog.

# ── Fact ids ──
# The id STRING is what crosses the JSON payload into the brain, keys the module rules, and
# prints in the HUD — so it follows one convention, snake_case, like control / module /
# mission / mode ids. The CONSTANT is SCREAMING_CASE; only its value is snake_case.
const WARNING_LIGHT := "warning_light" # master warning light colour
const STARTING_AIRPORT := "starting_airport"
const ARRIVING_AIRPORT := "arriving_airport"
const FLIGHT_NUMBER := "flight_number"

# ── Value pools ──
# Pool VALUES are shown to the pilot and read aloud, so they stay uppercase display text.
const GREEN := "GREEN"
const AMBER := "AMBER"
const RED := "RED"
const WARNING_COLOURS := [GREEN, AMBER, RED]

## The airport catalog. One entry = one object, so adding a property later (city, country,
## runway, ICAO…) only touches this list — nothing downstream changes.
##
## "code" is the CANONICAL value: the ONLY field that leaves this file. It is what the fact
## pools carry, what the rules compare, what the pilot reads aloud and what a letter-wheel
## module spells. Every other field is looked up here on demand (airport_name()), so the
## puzzle engine never learns that airports have names.
const AIRPORTS := [
	{"code": "OLY", "name": "OLYMPIA"},
	{"code": "BCN", "name": "BARCELONE"},
	{"code": "LHR", "name": "LONDRES HEATHROW"},
	{"code": "JFK", "name": "NEW YORK JFK"},
	{"code": "CDG", "name": "PARIS CHARLES DE GAULLE"},
	{"code": "MAD", "name": "MADRID"},
]

## Which field of an airport object is the canonical value. Named once so the accessors below
## are the only place that knows the field's spelling.
const AIRPORT_KEY := "code"

## The codes alone, in catalog order — the form a letter-wheel generator needs.
static func airport_codes() -> Array:
	var codes: Array = []
	for a in AIRPORTS:
		codes.append(a[AIRPORT_KEY])
	return codes

## Full name for a code. Falls back to the code itself so nothing ever renders blank.
static func airport_name(code: String) -> String:
	for a in AIRPORTS:
		if a[AIRPORT_KEY] == code:
			return a["name"]
	return code

## Every fact the game knows about, keyed by id. A def declares either
## "values" (pick one from the pool) or "gen":"number" with "min"/"max".
##
## "display" says WHERE in the cockpit the fact is shown (a DashboardLayout fact anchor).
## Anchors are fixed cockpit locations with no relation to where the module reading the fact
## was placed — a placard next to its own module would leak the association and hand the crew
## a large part of the puzzle. Same reason KTANE keeps edgework on the bomb's sides.
static func catalog() -> Dictionary:
	return {
		WARNING_LIGHT: {
			"id": WARNING_LIGHT, "values": WARNING_COLOURS,
			"label": "MASTER WARNING",
			"display": {"anchor": "glareshield"},
		},
		STARTING_AIRPORT: {
			"id": STARTING_AIRPORT, "values": airport_codes(),
			"label": "DEPARTURE",
			"display": {"anchor": "window_sticker"},
		},
		ARRIVING_AIRPORT: {
			"id": ARRIVING_AIRPORT, "values": airport_codes(),
			"label": "DESTINATION",
			"display": {"anchor": "side_panel"},
		},
		FLIGHT_NUMBER: {
			"id": FLIGHT_NUMBER, "gen": "number", "min": 1000, "max": 9999,
			"label": "FLIGHT No.",
			"display": {"anchor": "yoke_tag"},
		},
	}

static func has(id: String) -> bool:
	return catalog().has(id)

## The fact definition in the shape CockpitBrain.LoadManualJson expects. Empty when unknown.
static func def(id: String) -> Dictionary:
	return catalog().get(id, {})

static func ids() -> Array:
	return catalog().keys()
