class_name CockpitCampaign
extends RefCounted

## THE CAMPAIGN — an ordered, hand-authored list of missions, KTANE-style.
##
## Difficulty is two knobs and nothing else: WHICH module types are on the dashboard,
## and HOW MANY. A module type's complexity is inherent to the type (it lives in the
## module's own file); the campaign never rates or weights a module, it only picks.
##
## Authoring rule: introduce exactly ONE new module type per mission, keep it next to
## types the crew already knows, and only raise the count once the new type has been
## taught. Slots a mission does not fill stay blank on the dashboard — an early mission
## is meant to LOOK easy.
##
## A mission holds module ids only. Adding a module type never touches this file;
## adding a mission never touches a module file.
##
## Fields:
##   id      unique mission key (also the save-progress key)
##   name    shown on the mission select / loading screen
##   time    seconds on the clock, before the difficulty mode's time_scale
##   lives   LAND attempts, before the difficulty mode's lives_bonus. 1 = a wrong
##           configuration crashes on the first attempt. A failed attempt costs a life
##           and NOTHING else — no hidden clock penalty, no surprises.
##   modules module ids from ModuleRegistry, in dashboard order

static func missions() -> Array:
	return [
		{
			"id": "m01",
			"name": "First Officer",
			"time": 300,
			"lives": 3,
			"modules": [ModuleSwitch.ID, ModuleDial.ID],
		},
		{
			"id": "m02",
			"name": "Crosswind",
			"time": 300,
			"lives": 3,
			"modules": [ModuleSwitch.ID, ModuleDial.ID, ModuleLever.ID],
		},
		{
			"id": "m03",
			"name": "Night Approach",
			"time": 270,
			"lives": 2,
			"modules": [ModuleSwitch.ID, ModuleDial.ID, ModuleLever.ID],
		},
		{
			"id": "m04",
			"name": "Short Field",
			"time": 240,
			"lives": 1,
			"modules": [ModuleSwitch.ID, ModuleDial.ID, ModuleLever.ID],
		},
	]

static func count() -> int:
	return missions().size()

## The mission with this id, or an empty dictionary when unknown.
static func mission(id: String) -> Dictionary:
	for m in missions():
		if m.get("id", "") == id:
			return m
	return {}

## The mission at this position in the campaign order, or an empty dictionary.
static func mission_at(index: int) -> Dictionary:
	var all := missions()
	if index < 0 or index >= all.size():
		return {}
	return all[index]

## Catches a duplicated mission id, an empty module list, or a mission naming a module
## type that is not registered. Returns an empty array when the campaign is clean.
static func validate() -> Array:
	var errors: Array = []
	var seen: Dictionary = {}
	for m in missions():
		var id: String = m.get("id", "")
		if id.is_empty():
			errors.append("mission with empty id")
			continue
		if seen.has(id):
			errors.append("mission '%s': duplicate id" % id)
		seen[id] = true
		if int(m.get("time", 0)) <= 0:
			errors.append("mission '%s': time must be > 0" % id)
		if int(m.get("lives", 0)) < 1:
			errors.append("mission '%s': lives must be >= 1" % id)
		var mods: Array = m.get("modules", [])
		if mods.is_empty():
			errors.append("mission '%s': no modules" % id)
		for module_id in mods:
			if not ModuleRegistry.has(module_id):
				errors.append("mission '%s': unknown module '%s'" % [id, module_id])
	return errors
