extends RefCounted
class_name ManualEngine

## Owns the MANUAL: per-module ordered decision lists (if / else-if / else) and the
## condition engine that evaluates them. Derives each module's required state by walking
## its list top-to-bottom (first matching branch wins; a final "else" is the default).
##
## SINGLE SOURCE OF TRUTH FOR OPERATORS. Every operator is declared exactly ONCE, in OPS:
## its name (the const used as the key), what it does ("eval"), how the tower binder reads
## it ("phrase"), and whether a condition must carry a value ("needs_value"). Adding an
## operator = one entry here and nothing else.
##
## data/ops.gd only RE-EXPORTS the names so module files never spell one by hand. The
## direction matters: content (data/) may depend on the engine, never the reverse — it is
## the eval below that defines what an operator MEANS, so the engine owns it.

const VOWELS := "AEIOUY"  # Y counts as a vowel

# ── Operator names ──
const EQ := "eq"
const NEQ := "neq"
const STARTS := "starts"
const ENDS := "ends"
const CONTAINS := "contains"
const FIRST_VOWEL := "firstVowel"
const LAST_VOWEL := "lastVowel"
const FIRST_CONSONANT := "firstConsonant"
const LAST_CONSONANT := "lastConsonant"
const EVEN := "even"
const ODD := "odd"

## op name -> { eval: Callable(fact_value: String, cond_value: String) -> bool,
##              phrase: String, needs_value: bool }
## "phrase" is formatted with the fact name, then the condition value when needs_value.
static var OPS: Dictionary = {
	EQ: {
		"eval": func(v: String, x: String) -> bool: return v == x,
		"phrase": "%s is %s", "needs_value": true },
	NEQ: {
		"eval": func(v: String, x: String) -> bool: return v != x,
		"phrase": "%s is not %s", "needs_value": true },
	STARTS: {
		"eval": func(v: String, x: String) -> bool: return v.begins_with(x),
		"phrase": "%s starts with %s", "needs_value": true },
	ENDS: {
		"eval": func(v: String, x: String) -> bool: return v.ends_with(x),
		"phrase": "%s ends with %s", "needs_value": true },
	CONTAINS: {
		"eval": func(v: String, x: String) -> bool: return v.contains(x),
		"phrase": "%s contains %s", "needs_value": true },
	FIRST_VOWEL: {
		"eval": func(v: String, _x: String) -> bool: return v.length() > 0 and is_vowel(v[0]),
		"phrase": "first letter of %s is a vowel", "needs_value": false },
	LAST_VOWEL: {
		"eval": func(v: String, _x: String) -> bool: return v.length() > 0 and is_vowel(v[v.length() - 1]),
		"phrase": "last letter of %s is a vowel", "needs_value": false },
	FIRST_CONSONANT: {
		"eval": func(v: String, _x: String) -> bool: return v.length() > 0 and is_consonant(v[0]),
		"phrase": "first letter of %s is a consonant", "needs_value": false },
	LAST_CONSONANT: {
		"eval": func(v: String, _x: String) -> bool: return v.length() > 0 and is_consonant(v[v.length() - 1]),
		"phrase": "last letter of %s is a consonant", "needs_value": false },
	EVEN: {
		"eval": func(v: String, _x: String) -> bool: return v.is_valid_int() and int(v) % 2 == 0,
		"phrase": "%s is even", "needs_value": false },
	ODD: {
		"eval": func(v: String, _x: String) -> bool: return v.is_valid_int() and int(v) % 2 != 0,
		"phrase": "%s is odd", "needs_value": false },
}

static func has_op(op: String) -> bool:
	return OPS.has(op)

static func op_names() -> Array:
	return OPS.keys()

static func is_vowel(c: String) -> bool:
	return VOWELS.find(c.to_upper()) >= 0

static func is_consonant(c: String) -> bool:
	var u := c.to_upper()
	return u.length() == 1 and u >= "A" and u <= "Z" and not is_vowel(u)

var _modules: Dictionary = {}
var _order: Array = []

func clear() -> void:
	_modules.clear()
	_order.clear()

## Parse the "modules" object of the manual payload. Validates each control exists, each
## referenced fact exists, each op is known, each value-taking op actually got a value, and
## each set-label resolves to a real state. Returns a list of validation errors (empty = ok).
func load_modules(modules_dict, controls: ControlStore, facts: FactStore) -> Array:
	var errors: Array = []
	for control_id in modules_dict:
		if not controls.has(control_id):
			errors.append("module '%s': unknown control" % control_id)
		var branches: Array = []
		var bi := 0
		for b in modules_dict[control_id]:
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
					if not facts.has(c["fact"]):
						errors.append("%s branch %d: unknown fact '%s'" % [control_id, bi, c["fact"]])
					if not OPS.has(c["op"]):
						errors.append("%s branch %d: unknown op '%s'" % [control_id, bi, c["op"]])
					elif bool(OPS[c["op"]]["needs_value"]) and c["value"] == null:
						errors.append("%s branch %d: op '%s' needs a 'value'" % [control_id, bi, c["op"]])
					(branch["when"] as Array).append(c)
			var idx := controls.label_index(control_id, set_label)
			if controls.has(control_id) and idx < 0:
				errors.append("%s branch %d: no state '%s'" % [control_id, bi, set_label])
			branch["set_state"] = maxi(0, idx)
			branches.append(branch)
			bi += 1
		if not _modules.has(control_id):
			_order.append(control_id)
		_modules[control_id] = branches
	return errors

## Walk every module's decision list against the rolled facts; return {control_id: state}.
func derive(facts: FactStore) -> Dictionary:
	var required: Dictionary = {}
	for control_id in _order:
		for branch in _modules[control_id]:
			var match_ok: bool = branch["is_else"]
			if not branch["is_else"]:
				match_ok = true
				for cond in branch["when"]:
					if not _eval(cond, facts.fact_value(cond["fact"])):
						match_ok = false
						break
			if match_ok:
				required[control_id] = branch["set_state"]
				break
	return required

## Render the tower binder: each module as its numbered if/else-if/else list.
func manual_text(controls: ControlStore) -> String:
	var lines: Array = []
	for control_id in _order:
		lines.append(control_id.to_upper())
		var branches: Array = _modules[control_id]
		for i in branches.size():
			var br: Dictionary = branches[i]
			var label := controls.state_label(control_id, br["set_state"])
			if br["is_else"]:
				lines.append("  %d. else -> %s" % [i + 1, label])
			else:
				var parts: Array = []
				for c in br["when"]:
					parts.append(_phrase(c))
				var prefix := "if" if i == 0 else "else if"
				lines.append("  %d. %s %s -> %s" % [i + 1, prefix, " and ".join(parts), label])
	return "\n".join(lines)

func _eval(cond: Dictionary, fact_val) -> bool:
	var op: String = cond["op"]
	if not OPS.has(op):
		return false
	var val = cond["value"]
	return (OPS[op]["eval"] as Callable).call(str(fact_val), str(val) if val != null else "")

func _phrase(cond: Dictionary) -> String:
	var f: String = cond["fact"]
	var op: String = cond["op"]
	var val = cond["value"]
	var val_s := str(val) if val != null else ""
	if not OPS.has(op):
		return "%s %s %s" % [f, op, val_s]
	var spec: Dictionary = OPS[op]
	if bool(spec["needs_value"]):
		return (spec["phrase"] as String) % [f, val_s]
	return (spec["phrase"] as String) % f
