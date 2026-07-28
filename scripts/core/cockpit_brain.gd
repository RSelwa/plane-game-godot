extends Node
class_name CockpitBrain

## FACADE. The single authority the scenes talk to. Owns the three logic stores
## (controls / facts / manual), exposes the public API as thin delegates, and turns state
## changes into the `state_changed` signal. All heavy logic lives in the RefCounted stores;
## this file stays small no matter how many controls or modules a round has.
##
## Round flow: register controls -> load_manual_json(...) -> generate_flight(seed).

signal state_changed(id: String, state: int)

var _controls := ControlStore.new()
var _facts := FactStore.new()
var _manual := ManualEngine.new()
var _manual_errors: Array = []

# --- Controls (delegate to ControlStore) -----------------------------------------

func register_control(id: String, state_labels) -> void:
	_controls.register_control(id, state_labels)

func num_states(id: String) -> int:
	return _controls.num_states(id)

func get_state(id: String) -> int:
	return _controls.get_state(id)

func state_label(id: String, state: int) -> String:
	return _controls.state_label(id, state)

func label_index(id: String, label: String) -> int:
	return _controls.label_index(id, label)

func request_cycle(id: String) -> int:
	var s := _controls.request_cycle(id)
	if s >= 0:
		state_changed.emit(id, s)
	return s

func set_state(id: String, state: int) -> void:
	var s := _controls.set_state(id, state)
	if s >= 0:
		state_changed.emit(id, s)

func set_required(id: String, state: int) -> void:
	_controls.set_required(id, state)

func clear_required() -> void:
	_controls.clear_required()

func has_required(id: String) -> bool:
	return _controls.has_required(id)

func required_state(id: String) -> int:
	return _controls.required_state(id)

func is_valid() -> bool:
	return _controls.is_valid()

# --- Facts (delegate to FactStore) ------------------------------------------------

func fact_ids() -> Array:
	return _facts.fact_ids()

func fact_value(id: String) -> String:
	return _facts.fact_value(id)

# --- Manual load + validation -----------------------------------------------------

## Load facts + manual from a JSON string. Controls must already be registered so labels
## resolve. Returns "OK" or a "|"-joined list of validation errors (also pushed as engine
## errors). Splits the payload: facts to the FactStore, modules to the ManualEngine.
func load_manual_json(json: String) -> String:
	_facts.clear()
	_manual.clear()
	_manual_errors.clear()
	var root = JSON.parse_string(json)
	if typeof(root) != TYPE_DICTIONARY:
		_manual_errors.append("JSON parse error: root is not an object")
		_flush_errors()
		return " | ".join(_manual_errors)
	_manual_errors.append_array(_facts.load_defs(root.get("facts", [])))
	_manual_errors.append_array(_manual.load_modules(root.get("modules", {}), _controls, _facts))
	_flush_errors()
	return "OK" if _manual_errors.is_empty() else " | ".join(_manual_errors)

func manual_ok() -> bool:
	return _manual_errors.is_empty()

func _flush_errors() -> void:
	for err in _manual_errors:
		push_error("CockpitManual: " + err)

# --- Flight generation ------------------------------------------------------------

## Roll the facts from the seed, then derive + apply each module's required state.
## Same seed => same flight.
func generate_flight(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_facts.roll(rng)
	_controls.clear_required()
	var required := _manual.derive(_facts)
	for control_id in required:
		_controls.set_required(control_id, required[control_id])

func manual_text() -> String:
	return _manual.manual_text(_controls)

# --- Self test (deterministic gate) -----------------------------------------------

## Self-contained logic test across the facade + stores. Returns a PASS/FAIL report.
## Run headless with scripts/tests/brain_test.gd.
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
	var last_vowel := ap.length() > 0 and "AEIOUY".find(ap[ap.length() - 1].to_upper()) >= 0
	var fn := c.fact_value("flight_number")
	var even := fn.is_valid_int() and int(fn) % 2 == 0
	var expect := 0 if last_vowel else (2 if even else 1)
	var deriv := load_res == "OK" and c.required_state("lv") == expect
	log.append("decision-list(ap=%s,fn=%s) got=%d exp=%d %s" % [ap, fn, c.required_state("lv"), expect, "OK" if deriv else "FAIL"])
	c.free()

	var bad := CockpitBrain.new()
	bad.register_control("lv", ["UP", "DOWN"])
	var badres := bad.load_manual_json("{\"facts\":[{\"id\":\"F\",\"values\":[\"X\"]}],\"modules\":{\"ghost\":[{\"else\":\"UP\"}]}}")
	var caught := badres != "OK"
	log.append("validation caught bad control=%s %s" % [caught, "OK" if caught else "FAIL"])
	bad.free()

	var all_ok := v1 and v2 and v3 and deriv and caught
	return ("SELFTEST PASS :: " if all_ok else "SELFTEST FAIL :: ") + " | ".join(log)
