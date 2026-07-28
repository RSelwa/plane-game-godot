extends RefCounted
class_name FactStore

## Owns the flight FACTS (edgework the pilot reads). Loads their definitions from the
## manual payload, rolls a value per fact from the seed. Read-only to the rest of the game.

var _defs: Dictionary = {}
var _order: Array = []
var _values: Dictionary = {}

func clear() -> void:
	_defs.clear()
	_order.clear()
	_values.clear()

## Parse the "facts" array of the manual payload. Returns a list of validation errors
## (empty = ok). Each fact declares either "values":[..] or "gen":"number"+min/max.
func load_defs(facts_array) -> Array:
	var errors: Array = []
	for f in facts_array:
		var id := str(f.get("id", ""))
		var def := {"values": [], "gen": "", "min": 0, "max": 0}
		if f.has("values"):
			for v in f["values"]:
				(def["values"] as Array).append(str(v))
		if f.has("gen"):
			def["gen"] = str(f["gen"])
			def["min"] = int(f.get("min", 0))
			def["max"] = int(f.get("max", 0))
		if id.is_empty():
			errors.append("fact with empty id")
		elif (def["values"] as Array).is_empty() and def["gen"] == "":
			errors.append("fact '%s': needs 'values' or 'gen'" % id)
		else:
			if not _defs.has(id):
				_order.append(id)
			_defs[id] = def
			_values[id] = def["values"][0] if not (def["values"] as Array).is_empty() else str(def["min"])
	return errors

func has(id: String) -> bool:
	return _defs.has(id)

func fact_ids() -> Array:
	return _order.duplicate()

func fact_value(id: String) -> String:
	return _values.get(id, "?")

## Roll every fact from the seeded rng, in stable declaration order (determinism).
func roll(rng: RandomNumberGenerator) -> void:
	for id in _order:
		var def: Dictionary = _defs[id]
		var values: Array = def["values"]
		if not values.is_empty():
			_values[id] = values[rng.randi_range(0, values.size() - 1)]
		elif def["gen"] == "number":
			_values[id] = str(rng.randi_range(int(def["min"]), int(def["max"])))
