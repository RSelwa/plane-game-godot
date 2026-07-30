class_name DashboardLayout
extends RefCounted

## THE DASHBOARD — 12 module slots in two zones, plus the fixed anchors the facts live on.
##
##   OVERHEAD   [ ][ ][ ][ ]          4 slots, one row, above the windshield
##   ---------- windshield ----------  no slots; this gap is what makes it read as a cockpit
##   MAIN       [ ][ ][ ][ ]          8 slots, two rows, the panel in front of the pilot
##              [ ][ ][ ][ ]
##
## Splitting the grid in two is deliberate: the pilot has to look in two places, and the
## overview camera has to cover both. Slots a mission does not fill stay BLANK (a plate) —
## an early two-module mission is meant to look almost empty, and that is the difficulty tell.
##
## Slot ids are generated, not hand-listed: "<zone>_r<row>_c<col>" (e.g. "main_r1_c3").
## The cockpit scene's marker nodes must use these exact names so the spawner can match them.
##
## FACT ANCHORS are NOT slots. Facts live at fixed cockpit locations that have nothing to do
## with where the module reading them ended up — same reason KTANE puts edgework on the bomb's
## sides. A placard sitting next to the module that reads it would leak the association and
## give away a large part of the puzzle.

const ZONE_OVERHEAD := "overhead"
const ZONE_MAIN := "main"

## Zone geometry. Rows/cols are the logical grid; the scene owns the actual 3D positions.
static func zones() -> Dictionary:
	return {
		ZONE_OVERHEAD: {"id": ZONE_OVERHEAD, "name": "OVERHEAD PANEL", "rows": 1, "cols": 4},
		ZONE_MAIN: {"id": ZONE_MAIN, "name": "MAIN PANEL", "rows": 2, "cols": 4},
	}

static func slot_id(zone: String, row: int, col: int) -> String:
	return "%s_r%d_c%d" % [zone, row, col]

## Every slot, in a fixed order: overhead left-to-right, then main top-left reading order.
static func slots() -> Array:
	var out: Array = []
	for zone_id in [ZONE_OVERHEAD, ZONE_MAIN]:
		var z: Dictionary = zones()[zone_id]
		for row in int(z["rows"]):
			for col in int(z["cols"]):
				out.append({"id": slot_id(zone_id, row, col), "zone": zone_id, "row": row, "col": col})
	return out

static func slot_count() -> int:
	return slots().size()

## Fixed cockpit locations where facts are displayed. Deliberately unrelated to module slots.
## "style" is a hint for the prop the scene spawns; the scene owns the geometry.
static func fact_anchors() -> Dictionary:
	return {
		"glareshield": {"id": "glareshield", "name": "Glareshield", "style": "light"},
		"yoke_tag": {"id": "yoke_tag", "name": "Yoke tag", "style": "placard"},
		"window_sticker": {"id": "window_sticker", "name": "Window frame sticker", "style": "sticker"},
		"side_panel": {"id": "side_panel", "name": "Side panel plate", "style": "placard"},
	}

static func has_anchor(id: String) -> bool:
	return fact_anchors().has(id)

# ── Placement ────────────────────────────────────────────────────────────────────────
# Seeded and deterministic: the same (mission modules, seed) always produces the same
# dashboard, so a shared seed reproduces the whole flight including where things sit.

static func _allowed_zones(module_type: String) -> Array:
	var z: Array = ModuleRegistry.def(module_type).get("zones", [])
	return z if not z.is_empty() else [ZONE_OVERHEAD, ZONE_MAIN]

## Assign each module instance a free slot. Every module occupies exactly one slot. Ties
## break on instance id so the order never depends on array iteration, and a shared seed
## reproduces the same dashboard.
## Returns { "placements": { instance_id: {zone,row,col,slot_id} },
##           "empty": [slot ids left blank], "unplaced": [instance ids that did not fit] }.
static func place(instances: Array[ModuleInstance], seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var order: Array = instances.duplicate()
	order.sort_custom(func(a, b): return a.id < b.id)

	var taken: Dictionary = {}
	var placements: Dictionary = {}
	var unplaced: Array = []

	for module in order:
		var candidates: Array = []
		for zone_id in _allowed_zones(module.type):
			if not zones().has(zone_id):
				push_error("DashboardLayout: module '%s' wants unknown zone '%s'" % [module.type, zone_id])
				continue
			var z: Dictionary = zones()[zone_id]
			for row in int(z["rows"]):
				for col in int(z["cols"]):
					if not taken.has(slot_id(zone_id, row, col)):
						candidates.append({"zone": zone_id, "row": row, "col": col})
		if candidates.is_empty():
			unplaced.append(module.id)
			push_error("DashboardLayout: no room for module '%s'" % module.id)
			continue
		var pick: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		var sid := slot_id(pick["zone"], pick["row"], pick["col"])
		taken[sid] = module.id
		placements[module.id] = {
			"zone": pick["zone"],
			"row": pick["row"],
			"col": pick["col"],
			"slot_id": sid,
		}

	var empty: Array = []
	for slot in slots():
		if not taken.has(slot["id"]):
			empty.append(slot["id"])

	return {"placements": placements, "empty": empty, "unplaced": unplaced}

## Catches a module declaring an unknown zone, and a fact pointing at an anchor that does not
## exist. Returns an empty array when the layout is coherent.
static func validate() -> Array:
	var errors: Array = []
	for module_id in ModuleRegistry.ids():
		for zone_id in _allowed_zones(module_id):
			if not zones().has(zone_id):
				errors.append("module '%s': unknown zone '%s'" % [module_id, zone_id])
	for fact_id in CockpitFacts.ids():
		var anchor: String = CockpitFacts.def(fact_id).get("display", {}).get("anchor", "")
		if anchor.is_empty():
			errors.append("fact '%s': no display anchor" % fact_id)
		elif not has_anchor(anchor):
			errors.append("fact '%s': unknown anchor '%s'" % [fact_id, anchor])
	return errors
