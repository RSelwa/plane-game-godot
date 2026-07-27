class_name CockpitModes
extends RefCounted

## DIFFICULTY MODES — pure modifiers on top of an authored mission.
##
## The mission stays the authored truth; a mode only adjusts it. Adding a mode never
## touches the campaign. Everything a mode changes is announced BEFORE the round starts,
## so nothing a mode does can be a surprise mid-flight.
##
## Fields:
##   lives_bonus  added to the mission's lives (result floored at 1)
##   time_scale   multiplies the mission's clock (> 1 is friendlier)
##   feedback     what a FAILED land attempt tells the crew:
##                  FEEDBACK_NONE  "Landing aborted."          — tower re-derives from scratch
##                  FEEDBACK_COUNT "3 systems misconfigured."  — the crew learns how wrong they are
##                There is deliberately no "name the wrong module" level: with several
##                attempts it collapses into brute force.
##                The post-round recap always shows the FULL per-module breakdown
##                regardless of mode — that is where learning happens, and it is free.

const FEEDBACK_NONE := "none"
const FEEDBACK_COUNT := "count"

const RELAXED := "relaxed"
const STANDARD := "standard"
const IRONMAN := "ironman"

const DEFAULT_MODE := STANDARD

static func modes() -> Dictionary:
	return {
		RELAXED: {
			"id": RELAXED,
			"name": "Relaxed",
			"lives_bonus": 2,
			"time_scale": 1.25,
			"feedback": FEEDBACK_COUNT,
		},
		STANDARD: {
			"id": STANDARD,
			"name": "Standard",
			"lives_bonus": 0,
			"time_scale": 1.0,
			"feedback": FEEDBACK_COUNT,
		},
		IRONMAN: {
			"id": IRONMAN,
			"name": "Ironman",
			"lives_bonus": 0,
			"time_scale": 0.85,
			"feedback": FEEDBACK_NONE,
		},
	}

static func ids() -> Array:
	return modes().keys()

## The mode definition, falling back to the default mode when the id is unknown.
static func mode(id: String) -> Dictionary:
	return modes().get(id, modes()[DEFAULT_MODE])

## LAND attempts the crew actually gets. Never below 1 — a mode may only ever be kinder
## than the mission, and a mission with no attempt at all is not a mission.
static func effective_lives(mission: Dictionary, mode_id: String) -> int:
	return maxi(1, int(mission.get("lives", 1)) + int(mode(mode_id).get("lives_bonus", 0)))

## Seconds on the clock once the mode's scale is applied.
static func effective_time(mission: Dictionary, mode_id: String) -> int:
	return maxi(1, int(round(float(mission.get("time", 0)) * float(mode(mode_id).get("time_scale", 1.0)))))

## What a failed LAND attempt is allowed to reveal in-round.
static func feedback(mode_id: String) -> String:
	return mode(mode_id).get("feedback", FEEDBACK_COUNT)
