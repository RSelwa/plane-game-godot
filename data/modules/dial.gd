class_name ModuleDial
extends RefCounted

## ARMING DIAL — introductory module. One numeric fact, one parity test.
## Difficulty tier: introductory. Pairs well with the switch in a first mission: the
## pilot reads a number, the tower applies a single rule.

const ID := "dial"

# ── States (order defines the cycle order in the cockpit) ──
const SAFE := "SAFE"
const ARMED := "ARMED"

static func def() -> Dictionary:
	return {
		"id": ID,
		"display": "ARMING DIAL",
		"scene": "res://scenes/modules/dial.tscn",
		"footprint": [1, 1],
		"check": "state_match",
		"states": [SAFE, ARMED],
		"facts": [CockpitFacts.FLIGHT_NUMBER],
		"rules": [
			{ "when": [ { "fact": CockpitFacts.FLIGHT_NUMBER, "op": CockpitOps.EVEN } ], "set": SAFE },
			{ "else": ARMED },
		],
	}
