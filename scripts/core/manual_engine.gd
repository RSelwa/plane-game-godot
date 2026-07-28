extends RefCounted
class_name ManualEngine

## Owns the MANUAL: per-module ordered decision lists (if / else-if / else) and the
## condition engine that evaluates them. Derives each module's required state by walking
## its list top-to-bottom (first matching branch wins; a final "else" is the default).

const VOWELS := "AEIOUY"  # Y counts as a vowel
const KNOWN_OPS := [
	"eq", "neq", "starts", "ends", "contains",
	"firstVowel", "lastVowel", "firstConsonant", "lastConsonant", "even", "odd",
]

var _modules: Dictionary = {}
var _order: Array = []

func clear() -> void:
	_modules.clear()
	_order.clear()

## Parse the "modules" object of the manual payload. Validates each control exists, each
## referenced fact exists, each op is known, and each set-label resolves to a real state.
## Returns a list of validation errors (empty = ok).
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
					if not KNOWN_OPS.has(c["op"]):
						errors.append("%s branch %d: unknown op '%s'" % [control_id, bi, c["op"]])
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
