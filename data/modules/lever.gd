class_name ModuleLever
extends RefCounted

## GEAR LEVER — three states, three facts, letter-class tests.
## Difficulty tier: intermediate. Harder than the switch/dial not because the list is
## longer but because the pilot must SPELL an airport code aloud and the tower must
## classify its letters: the communication load is the difficulty.

const ID := "lever"

# ── States (order defines the cycle order in the cockpit) ──
const UP := "UP"
const CENTER := "CENTER"
const DOWN := "DOWN"

static func def() -> Dictionary:
	return {
		"id": ID,
		"display": "GEAR LEVER",
		"scene": "res://scenes/modules/lever.tscn",
		"footprint": [1, 1],
		"zones": [DashboardLayout.ZONE_MAIN],   # a gear lever overhead would read as nonsense
		"check": "state_match",
		"states": [UP, CENTER, DOWN],
		"facts": [CockpitFacts.STARTING_AIRPORT, CockpitFacts.ARRIVING_AIRPORT, CockpitFacts.WARNING_LIGHT],
		"rules": [
			{ "when": [ { "fact": CockpitFacts.STARTING_AIRPORT, "op": CockpitOps.LAST_VOWEL } ], "set": UP },
			{ "when": [ { "fact": CockpitFacts.ARRIVING_AIRPORT, "op": CockpitOps.FIRST_CONSONANT } ], "set": CENTER },
			{ "when": [ { "fact": CockpitFacts.WARNING_LIGHT, "op": CockpitOps.EQ, "value": CockpitFacts.RED } ], "set": DOWN },
			{ "else": UP },
		],
	}
