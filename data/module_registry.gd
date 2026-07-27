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
static func validate() -> Array:
	var errors: Array = []
	for id in defs():
		var d: Dictionary = def(id)
		if d.get("id", "") != id:
			errors.append("module '%s': def().id is '%s'" % [id, d.get("id", "")])
		var states: Array = d.get("states", [])
		if states.size() < 2:
			errors.append("module '%s': needs at least 2 states" % id)
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
