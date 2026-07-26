class_name CockpitManual
extends RefCounted

## THE MANUAL — edit this file to change the puzzle, then press F6 (no restart).
##
## Declare every value ONCE as a constant and reuse it by name; a typo becomes an
## "undefined constant" the editor flags instantly. The C# brain also validates the
## data on load (unknown fact / control / op / label => a clear error).
##
## A MODULE is an ordered decision list. The brain walks it top-to-bottom and the FIRST
## branch whose conditions all pass sets the control's required state; the final "else"
## is the default. A branch's "when" is a list of conditions, ALL of which must hold (AND).
## A condition is { "fact": <fact>, "op": <op>, "value": <value?> } (value omitted for
## ops like even / lastVowel). Facts are generated from the round seed.

# ── Facts (edgework the pilot reads aloud to the tower) ──
const WARN := "WARN"                       # master warning light colour
const   GREEN := "GREEN"
const   AMBER := "AMBER"
const   RED := "RED"
const STARTING_AIRPORT := "starting_airport"
const ARRIVING_AIRPORT := "arriving_airport"
const FLIGHT_NUMBER := "flight_number"
const AIRPORTS := ["OLY", "BCN", "LHR", "JFK", "CDG", "MAD"]

# ── Condition operators ──
const EQ := "eq"
const NEQ := "neq"
const STARTS := "starts"
const ENDS := "ends"
const CONTAINS := "contains"
const FIRST_VOWEL := "firstVowel"
const LAST_VOWEL := "lastVowel"          # note: Y counts as a vowel
const FIRST_CONSONANT := "firstConsonant"
const LAST_CONSONANT := "lastConsonant"
const EVEN := "even"
const ODD := "odd"

# ── Controls and their state labels (must match the cockpit scene) ──
const SWITCH := "switch"
const   OFF := "OFF"
const   ON := "ON"
const DIAL := "dial"
const   SAFE := "SAFE"
const   ARMED := "ARMED"
const LEVER := "lever"
const   UP := "UP"
const   CENTER := "CENTER"
const   DOWN := "DOWN"

static func data() -> Dictionary:
	return {
		"facts": [
			{ "id": WARN, "values": [GREEN, AMBER, RED] },
			{ "id": STARTING_AIRPORT, "values": AIRPORTS },
			{ "id": ARRIVING_AIRPORT, "values": AIRPORTS },
			{ "id": FLIGHT_NUMBER, "gen": "number", "min": 1000, "max": 9999 },
		],
		"modules": {
			SWITCH: [
				{ "when": [ { "fact": WARN, "op": EQ, "value": GREEN } ], "set": OFF },
				{ "else": ON },
			],
			DIAL: [
				{ "when": [ { "fact": FLIGHT_NUMBER, "op": EVEN } ], "set": SAFE },
				{ "else": ARMED },
			],
			LEVER: [
				{ "when": [ { "fact": STARTING_AIRPORT, "op": LAST_VOWEL } ], "set": UP },
				{ "when": [ { "fact": ARRIVING_AIRPORT, "op": FIRST_CONSONANT } ], "set": CENTER },
				{ "when": [ { "fact": WARN, "op": EQ, "value": RED } ], "set": DOWN },
				{ "else": UP },
			],
		},
	}
