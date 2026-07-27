class_name ModuleSwitch
extends RefCounted

## MASTER SWITCH — the simplest module type. One fact, one condition.
## Difficulty tier: introductory. This is the module a first mission teaches with.
##
## A module file owns everything about its type: the prefab scene, the dashboard
## footprint, the states it can be in, the facts it reads, and the decision list that
## derives its required state. Nothing about a module lives in the campaign.

const ID := "switch"

# ── States (order defines the cycle order in the cockpit) ──
const OFF := "OFF"
const ON := "ON"

static func def() -> Dictionary:
	return {
		"id": ID,
		"display": "MASTER SWITCH",
		"scene": "res://scenes/modules/switch.tscn",
		"footprint": [1, 1],
		"zones": [DashboardLayout.ZONE_OVERHEAD, DashboardLayout.ZONE_MAIN],
		"check": "state_match",
		"states": [OFF, ON],
		"facts": [CockpitFacts.WARN],
		"rules": [
			{ "when": [ { "fact": CockpitFacts.WARN, "op": CockpitOps.EQ, "value": CockpitFacts.GREEN } ], "set": OFF },
			{ "else": ON },
		],
	}
