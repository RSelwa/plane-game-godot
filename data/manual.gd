class_name CockpitManual
extends RefCounted

## THE MANUAL — edit this file to change the puzzle, then press F6 (no restart).
##
## Declare every value ONCE as a constant, then reuse it by name. A typo becomes an
## "undefined constant" the editor flags immediately, so a rule can never silently
## reference the wrong string. The C# brain loads data() and validates it further
## (unknown control/label/cue => a clear error at load).
##
## A cue value ending in "*" is a PREFIX match (e.g. CODE "B*" = any code starting B).
## Rules apply top-to-bottom; the FIRST rule to constrain a control wins.

# ── Cues (the observables the pilot reads to the tower) ──
const WARN := "WARN"          # master warning light
const   GREEN := "GREEN"
const   AMBER := "AMBER"
const   RED := "RED"
const CODE := "CODE"          # system code printed in the cockpit
const   A1 := "A1"
const   B7 := "B7"
const   C3 := "C3"

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
		"cues": [
			{ "id": WARN, "values": [GREEN, AMBER, RED] },
			{ "id": CODE, "values": [A1, B7, C3] },
		],
		"rules": [
			{ "when": { WARN: GREEN },           "require": { SWITCH: OFF, DIAL: SAFE } },
			{ "when": { WARN: AMBER },            "require": { SWITCH: ON, DIAL: SAFE } },
			{ "when": { WARN: RED },              "require": { SWITCH: ON, DIAL: ARMED } },
			{ "when": { CODE: "A*" },             "require": { LEVER: UP } },
			{ "when": { CODE: "B*" },             "require": { LEVER: CENTER } },
			{ "when": { CODE: "C*" },             "require": { LEVER: DOWN } },
		],
	}
