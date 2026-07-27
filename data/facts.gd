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
const WARN := "WARN"                       # master warning light colour
const STARTING_AIRPORT := "starting_airport"
const ARRIVING_AIRPORT := "arriving_airport"
const FLIGHT_NUMBER := "flight_number"

# ── Value pools ──
const GREEN := "GREEN"
const AMBER := "AMBER"
const RED := "RED"
const WARN_COLOURS := [GREEN, AMBER, RED]

const AIRPORTS := ["OLY", "BCN", "LHR", "JFK", "CDG", "MAD"]

## Every fact the game knows about, keyed by id. A def declares either
## "values" (pick one from the pool) or "gen":"number" with "min"/"max".
static func catalog() -> Dictionary:
	return {
		WARN: { "id": WARN, "values": WARN_COLOURS },
		STARTING_AIRPORT: { "id": STARTING_AIRPORT, "values": AIRPORTS },
		ARRIVING_AIRPORT: { "id": ARRIVING_AIRPORT, "values": AIRPORTS },
		FLIGHT_NUMBER: { "id": FLIGHT_NUMBER, "gen": "number", "min": 1000, "max": 9999 },
	}

static func has(id: String) -> bool:
	return catalog().has(id)

## The fact definition in the shape CockpitBrain.LoadManualJson expects. Empty when unknown.
static func def(id: String) -> Dictionary:
	return catalog().get(id, {})

static func ids() -> Array:
	return catalog().keys()
