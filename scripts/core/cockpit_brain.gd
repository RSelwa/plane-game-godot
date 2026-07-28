extends Node
class_name CockpitBrain

## Authoritative cockpit state + the KTANE puzzle brain. Owns each control's current and
## required state, the flight FACTS (edgework the pilot reads), the MANUAL (per-module
## ordered decision lists), and landing validation. Presentation lives in the view scripts.
##
## Everything is generated from ONE seed (generate_flight): the facts are rolled, then each
## module's required state is DERIVED by walking its decision list top-to-bottom (first
## matching branch wins; a final "else" is the default). The required config is never stored
## as data -- it only exists as the consequence of facts + rules.

signal state_changed(id: String, state: int)

const VOWELS := "AEIOUY"  # Y counts as a vowel
const KNOWN_OPS := [
	"eq", "neq", "starts", "ends", "contains",
	"firstVowel", "lastVowel", "firstConsonant", "lastConsonant", "even", "odd",
]

# --- Controls ---------------------------------------------------------------------
var _labels: Dictionary = {}        # id -> Array[String] state labels
var _control_order: Array = []
var _state: Dictionary = {}         # id -> int current state
var _required: Dictionary = {}      # id -> int required state (derived)

# --- Facts (edgework the pilot reads to the tower) --------------------------------
var _fact_defs: Dictionary = {}     # id -> { values:Array, gen:String, min:int, max:int }
var _fact_order: Array = []
var _fact: Dictionary = {}          # id -> String rolled value

# --- Manual (per-module ordered decision lists) -----------------------------------
var _modules: Dictionary = {}       # id -> Array of branch dicts
var _module_order: Array = []
var _manual_errors: Array = []

# --- Controls API -----------------------------------------------------------------

func register_control(id: String, state_labels) -> void:
	if id.is_empty():
		push_error("CockpitBrain: empty control id ignored.")
		return
	if _labels.has(id):
		push_error("CockpitBrain: duplicate control id '%s' ignored." % id)
		return
	var src: Array = []
	if state_labels != null:
		for s in state_labels:
			src.append(str(s))
	var n := maxi(1, src.size())
	var labels: Array = []
	for i in n:
		labels.append(src[i] if i < src.size() else str(i))
	_labels[id] = labels
	_control_order.append(id)
	_state[id] = 0

func num_states(id: String) -> int:
	return (_labels[id] as Array).size() if _labels.has(id) else 0

func get_state(id: String) -> int:
	return _state.get(id, -1)

func state_label(id: String, state: int) -> String:
	if not _labels.has(id):
		return "?"
	var l: Array = _labels[id]
	return l[state] if state >= 0 and state < l.size() else "?"

func label_index(id: String, label: String) -> int:
	if not _labels.has(id):
		return -1
	var l: Array = _labels[id]
	for i in l.size():
		if l[i] == label:
			return i
	return -1

func request_cycle(id: String) -> int:
	if not _state.has(id):
		push_error("CockpitBrain: cycle unknown control '%s'." % id)
		return -1
	var n: int = (_labels[id] as Array).size()
	var s := (int(_state[id]) + 1) % n
	_state[id] = s
	state_changed.emit(id, s)
	return s

func set_state(id: String, state: int) -> void:
	if not _state.has(id):
		return
	var n: int = (_labels[id] as Array).size()
	_state[id] = ((state % n) + n) % n
	state_changed.emit(id, _state[id])

func set_required(id: String, state: int) -> void:
	_required[id] = state

func clear_required() -> void:
	_required.clear()

func has_required(id: String) -> bool:
	return _required.has(id)

func required_state(id: String) -> int:
	return _required.get(id, -1)

func is_valid() -> bool:
	for id in _required:
		if not _state.has(id):
			return false
		if int(_state[id]) != int(_required[id]):
			return false
	return true

# --- Facts API --------------------------------------------------------------------

func fact_ids() -> Array:
	return _fact_order.duplicate()

func fact_value(id: String) -> String:
	return _fact.get(id, "?")

# --- Manual load + validation -----------------------------------------------------

## Load facts + manual from a JSON string. Shape:
## { "facts":[{"id","values":[..]} | {"id","gen":"number","min","max"}],
##   "modules":{ controlId:[ {"when":[{"fact","op","value"?}],"set":label} , ... , {"else":label} ] } }
## Controls must already be registered so state labels resolve. Returns "OK" or a
## "|"-joined list of validation errors (also pushed as engine errors) -- a typo'd fact,
## control, op, or label is caught here, not as a silently-broken round.
func load_manual_json(json: String) -> String:
	_fact_defs.clear()
	_fact_order.clear()
	_fact.clear()
	_modules.clear()
	_module_order.clear()
	_manual_errors.clear()

	var root = JSON.parse_string(json)
	if typeof(root) != TYPE_DICTIONARY:
		_manual_errors.append("JSON parse error: root is not an object")
		_flush_errors()
		return " | ".join(_manual_errors)

	for f in root.get("facts", []):
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
			_manual_errors.append("fact with empty id")
		elif (def["values"] as Array).is_empty() and def["gen"] == "":
			_manual_errors.append("fact '%s': needs 'values' or 'gen'" % id)
		else:
			if not _fact_defs.has(id):
				_fact_order.append(id)
			_fact_defs[id] = def
			_fact[id] = def["values"][0] if not (def["values"] as Array).is_empty() else str(def["min"])

	for control_id in root.get("modules", {}):
		if not _labels.has(control_id):
			_manual_errors.append("module '%s': unknown control" % control_id)
		var branches: Array = []
		var bi := 0
		for b in root["modules"][control_id]:
			var branch := {"when": [], "is_else": false, "set_state": 0}
			var set_label := ""
			if b.has("else"):
				branch["is_else"] = true
				set_label = str(b["else"])
			else:
				set_label = str(b.get("set", ""))
				for cond in b.get("when", []):
					var c := {
						"fact": str(cond.get("fact", "")),
						"op": str(cond.get("op", "")),
						"value": str(cond["value"]) if cond.has("value") else null,
					}
					if not _fact_defs.has(c["fact"]):
						_manual_errors.append("%s branch %d: unknown fact '%s'" % [control_id, bi, c["fact"]])
					if not KNOWN_OPS.has(c["op"]):
						_manual_errors.append("%s branch %d: unknown op '%s'" % [control_id, bi, c["op"]])
					(branch["when"] as Array).append(c)
			var idx := label_index(control_id, set_label)
			if _labels.has(control_id) and idx < 0:
				_manual_errors.append("%s branch %d: no state '%s'" % [control_id, bi, set_label])
			branch["set_state"] = maxi(0, idx)
			branches.append(branch)
			bi += 1
		if not _modules.has(control_id):
			_module_order.append(control_id)
		_modules[control_id] = branches

	_flush_errors()
	return "OK" if _manual_errors.is_empty() else " | ".join(_manual_errors)

func manual_ok() -> bool:
	return _manual_errors.is_empty()

func _flush_errors() -> void:
	for err in _manual_errors:
		push_error("CockpitManual: " + err)

# --- Flight generation + derivation -----------------------------------------------

## Roll every fact from the seed (stable order = determinism), then DERIVE each module's
## required state by walking its decision list top-to-bottom; the FIRST branch whose
## conditions all pass wins (an "else" always passes). Same seed => same flight.
func generate_flight(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for id in _fact_order:
		var def: Dictionary = _fact_defs[id]
		var values: Array = def["values"]
		if not values.is_empty():
			_fact[id] = values[rng.randi_range(0, values.size() - 1)]
		elif def["gen"] == "number":
			_fact[id] = str(rng.randi_range(int(def["min"]), int(def["max"])))
	clear_required()
	for control_id in _module_order:
		for branch in _modules[control_id]:
			var match_ok: bool = branch["is_else"]
			if not branch["is_else"]:
				match_ok = true
				for cond in branch["when"]:
					if not _eval(cond, _fact.get(cond["fact"], "")):
						match_ok = false
						break
			if match_ok:
				_required[control_id] = branch["set_state"]
				break

## Render the tower binder: each module as its numbered if/else-if/else list.
func manual_text() -> String:
	var lines: Array = []
	for control_id in _module_order:
		lines.append(control_id.to_upper())
		var branches: Array = _modules[control_id]
		for i in branches.size():
			var br: Dictionary = branches[i]
			var label := state_label(control_id, br["set_state"])
			if br["is_else"]:
				lines.append("  %d. else -> %s" % [i + 1, label])
			else:
				var parts: Array = []
				for c in br["when"]:
					parts.append(_phrase(c))
				var prefix := "if" if i == 0 else "else if"
				lines.append("  %d. %s %s -> %s" % [i + 1, prefix, " and ".join(parts), label])
	return "\n".join(lines)

# --- Condition engine -------------------------------------------------------------

func _eval(cond: Dictionary, fact_val) -> bool:
	var v := str(fact_val)
	var val = cond["value"]
	var val_s := str(val) if val != null else ""
	match cond["op"]:
		"eq": return v == val_s
		"neq": return v != val_s
		"starts": return v.begins_with(val_s)
		"ends": return v.ends_with(val_s)
		"contains": return v.contains(val_s)
		"firstVowel": return v.length() > 0 and _is_vowel(v[0])
		"lastVowel": return v.length() > 0 and _is_vowel(v[v.length() - 1])
		"firstConsonant": return v.length() > 0 and _is_consonant(v[0])
		"lastConsonant": return v.length() > 0 and _is_consonant(v[v.length() - 1])
		"even": return v.is_valid_int() and int(v) % 2 == 0
		"odd": return v.is_valid_int() and int(v) % 2 != 0
	return false

func _phrase(cond: Dictionary) -> String:
	var f: String = cond["fact"]
	var val = cond["value"]
	var val_s := str(val) if val != null else ""
	match cond["op"]:
		"eq": return "%s is %s" % [f, val_s]
		"neq": return "%s is not %s" % [f, val_s]
		"starts": return "%s starts with %s" % [f, val_s]
		"ends": return "%s ends with %s" % [f, val_s]
		"contains": return "%s contains %s" % [f, val_s]
		"firstVowel": return "first letter of %s is a vowel" % f
		"lastVowel": return "last letter of %s is a vowel" % f
		"firstConsonant": return "first letter of %s is a consonant" % f
		"lastConsonant": return "last letter of %s is a consonant" % f
		"even": return "%s is even" % f
		"odd": return "%s is odd" % f
	return "%s %s %s" % [f, cond["op"], val_s]

func _is_vowel(c: String) -> bool:
	return VOWELS.find(c.to_upper()) >= 0

func _is_consonant(c: String) -> bool:
	var u := c.to_upper()
	return u.length() == 1 and u >= "A" and u <= "Z" and not _is_vowel(u)

# --- Self test (deterministic gate) -----------------------------------------------

## Self-contained logic test. Returns a PASS/FAIL report. Run headless with
## scripts/tests/brain_test.gd. Reproduces the old C# SelfTest coverage.
static func self_test() -> String:
	var log: Array = []

	var b := CockpitBrain.new()
	b.register_control("gear", ["UP", "DOWN"])
	b.set_required("gear", 1)
	var v1 := not b.is_valid()      # gear=0, need 1 -> invalid
	b.request_cycle("gear")
	var v2 := b.is_valid()          # gear=1 -> valid
	b.set_required("ghost", 0)
	var v3 := not b.is_valid()      # missing control -> invalid
	log.append("validate %s %s" % [v1 and v2 and v3, "OK" if (v1 and v2 and v3) else "FAIL"])
	b.free()

	# Decision-list derivation with real predicates.
	var c := CockpitBrain.new()
	c.register_control("lv", ["UP", "CENTER", "DOWN"])
	var manual := "{\"facts\":[" + \
		"{\"id\":\"starting_airport\",\"values\":[\"OLY\",\"BCN\"]}," + \
		"{\"id\":\"flight_number\",\"gen\":\"number\",\"min\":1000,\"max\":9999}]," + \
		"\"modules\":{\"lv\":[" + \
		"{\"when\":[{\"fact\":\"starting_airport\",\"op\":\"lastVowel\"}],\"set\":\"UP\"}," + \
		"{\"when\":[{\"fact\":\"flight_number\",\"op\":\"even\"}],\"set\":\"DOWN\"}," + \
		"{\"else\":\"CENTER\"}]}}"
	var load_res := c.load_manual_json(manual)
	c.generate_flight(4821)
	var ap := c.fact_value("starting_airport")
	var last_vowel := ap.length() > 0 and VOWELS.find(ap[ap.length() - 1].to_upper()) >= 0
	var fn := c.fact_value("flight_number")
	var even := fn.is_valid_int() and int(fn) % 2 == 0
	var expect := 0 if last_vowel else (2 if even else 1)
	var deriv := load_res == "OK" and c.required_state("lv") == expect
	log.append("decision-list(ap=%s,fn=%s) got=%d exp=%d %s" % [ap, fn, c.required_state("lv"), expect, "OK" if deriv else "FAIL"])
	c.free()

	# Validation catches a rule naming a control that doesn't exist.
	var bad := CockpitBrain.new()
	bad.register_control("lv", ["UP", "DOWN"])
	var badres := bad.load_manual_json("{\"facts\":[{\"id\":\"F\",\"values\":[\"X\"]}],\"modules\":{\"ghost\":[{\"else\":\"UP\"}]}}")
	var caught := badres != "OK"
	log.append("validation caught bad control=%s %s" % [caught, "OK" if caught else "FAIL"])
	bad.free()

	var all_ok := v1 and v2 and v3 and deriv and caught
	return ("SELFTEST PASS :: " if all_ok else "SELFTEST FAIL :: ") + " | ".join(log)
