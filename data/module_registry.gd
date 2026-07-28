class_name ModuleRegistry
extends RefCounted

## THE MODULE REGISTRY — the one place that knows every module type exists.
##
## A mission (see CockpitCampaign) names module ids and nothing else; the registry
## resolves an id to its full definition. Adding a module type = add a file under
## data/modules/ and one line in defs(). Nothing else in the game changes.
##
## build_manual_data() is the bridge to the C# brain: it turns a mission's module list
## into exactly the { "facts": [...], "modules": {...} } shape CockpitBrain.LoadManualJson
## already eats, with the fact set narrowed to the union of what those modules read.

## Every registered module type, keyed by id.
static func defs() -> Dictionary:
	return {
		ModuleSwitch.ID: ModuleSwitch.def(),
		ModuleDial.ID: ModuleDial.def(),
		ModuleLever.ID: ModuleLever.def(),
	}

static func ids() -> Array:
	return defs().keys()

static func has(id: String) -> bool:
	return defs().has(id)

## Full definition for a module id. Empty dictionary when the id is unknown.
static func def(id: String) -> Dictionary:
	return defs().get(id, {})

## Assemble the manual payload for one mission: the union of the facts its modules read
## (in first-seen order, deduplicated) plus each module's decision list, keyed by module id.
## Module id == control id for state_match modules, which is what the brain expects today.
static func build_manual_data(module_ids: Array) -> Dictionary:
	var facts: Array = []
	var seen: Dictionary = {}
	var modules: Dictionary = {}
	var all := defs()
	for id in module_ids:
		if not all.has(id):
			push_error("ModuleRegistry: mission names unknown module '%s'" % id)
			continue
		var d: Dictionary = all[id]
		for fact_id in d.get("facts", []):
			if seen.has(fact_id):
				continue
			seen[fact_id] = true
			var fact_def := CockpitFacts.def(fact_id)
			if fact_def.is_empty():
				push_error("ModuleRegistry: module '%s' reads unknown fact '%s'" % [id, fact_id])
				continue
			facts.append(fact_def)
		modules[id] = d.get("rules", [])
	return { "facts": facts, "modules": modules }

## Static sanity pass over every registered module: catches a typo'd fact, an unknown
## operator, or a rule setting a state the module does not declare. Returns an empty
## array when the registry is clean. Cheap enough to run on load.
##
## Also guards the two things that CANNOT be reduced to a single declaration by the language
## and so have to be kept honest by a check instead:
##   - a prefab re-declaring control_id / state_labels (a .tscn stores literals, it cannot
##     reference a constant), which would silently shadow the data file
##   - a fact id drifting off snake_case, the convention the id strings share with control /
##     module / mission / mode ids
static func validate() -> Array:
	var errors: Array = []
	errors.append_array(_validate_fact_id_convention())
	for id in defs():
		var d: Dictionary = def(id)
		if d.get("id", "") != id:
			errors.append("module '%s': def().id is '%s'" % [id, d.get("id", "")])
		var states: Array = d.get("states", [])
		if states.size() < 2:
			errors.append("module '%s': needs at least 2 states" % id)
		errors.append_array(_validate_prefab_declares_nothing(id, d))
		for fact_id in d.get("facts", []):
			if not CockpitFacts.has(fact_id):
				errors.append("module '%s': unknown fact '%s'" % [id, fact_id])
		var declared_facts: Array = d.get("facts", [])
		var rules: Array = d.get("rules", [])
		var branch := 0
		var has_else := false
		for rule in rules:
			var set_label: String = rule.get("else", rule.get("set", ""))
			if rule.has("else"):
				has_else = true
			if not states.has(set_label):
				errors.append("module '%s' branch %d: sets undeclared state '%s'" % [id, branch, set_label])
			for cond in rule.get("when", []):
				var fact_id: String = cond.get("fact", "")
				if not CockpitFacts.has(fact_id):
					errors.append("module '%s' branch %d: unknown fact '%s'" % [id, branch, fact_id])
				elif not declared_facts.has(fact_id):
					errors.append("module '%s' branch %d: reads fact '%s' missing from its 'facts' list" % [id, branch, fact_id])
				if not CockpitOps.is_known(cond.get("op", "")):
					errors.append("module '%s' branch %d: unknown op '%s'" % [id, branch, cond.get("op", "")])
			branch += 1
		if not has_else:
			errors.append("module '%s': decision list has no final 'else' default" % id)
	return errors

## A module's prefab must leave control_id and state_labels EMPTY: ModuleSpawner pushes both
## from def() at spawn time. A prefab that fills them in is a second source of truth the
## other checks here cannot see — they validate the rules against def()["states"], while the
## brain would be registering whatever the scene carried.
static func _validate_prefab_declares_nothing(id: String, d: Dictionary) -> Array:
	var errors: Array = []
	var scene_path: String = d.get("scene", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		errors.append("module '%s': missing scene '%s'" % [id, scene_path])
		return errors
	var packed: PackedScene = load(scene_path)
	if packed == null:
		errors.append("module '%s': could not load '%s'" % [id, scene_path])
		return errors
	var probe := packed.instantiate()
	if probe is CockpitControl:
		var control := probe as CockpitControl
		if not control.control_id.is_empty():
			errors.append("module '%s': prefab hardcodes control_id '%s' — remove it, the spawner pushes it" % [id, control.control_id])
		if control.state_labels.size() > 0:
			errors.append("module '%s': prefab hardcodes state_labels %s — remove it, the spawner pushes def().states" % [id, str(control.state_labels)])
	else:
		errors.append("module '%s': prefab root is not a CockpitControl" % id)
	probe.free()
	return errors

## Fact id STRINGS share one convention with control / module / mission / mode ids:
## lowercase snake_case. The constant naming them stays SCREAMING_CASE.
static func _validate_fact_id_convention() -> Array:
	var errors: Array = []
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_"
	for fact_id in CockpitFacts.ids():
		var s := str(fact_id)
		for i in s.length():
			if allowed.find(s[i]) < 0:
				errors.append("fact '%s': id must be lowercase snake_case" % s)
				break
	return errors
