extends Node3D
class_name ModuleSpawner

## Builds the dashboard for one mission: asks DashboardLayout where each module goes,
## instances its prefab into the matching slot marker, and drops a blank plate in every
## slot the mission did not use.
##
## The spawner owns no game logic — it neither derives nor validates anything. It turns a
## mission's module id list into scene nodes and hands them back; the CockpitManager wires
## them to the brain. Slot marker nodes in the scene MUST be named with the ids generated
## by DashboardLayout.slot_id() ("<zone>_r<row>_c<col>"), which is the whole matching key.

signal modules_spawned(controls: Dictionary)

const BLANK_PLATE_SCENE := "res://scenes/modules/blank_plate.tscn"

## Nodes created by the last spawn, cleared on the next one.
var _spawned: Array[Node] = []

## module id -> the CockpitControl node instanced for it (last spawn).
var _controls: Dictionary = {}

func controls() -> Dictionary:
	return _controls

## Remove everything the previous spawn created, leaving the markers themselves intact.
func clear() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	_controls.clear()

## Build the dashboard for `module_ids`, placed deterministically from `seed_value`.
## Returns { module_id: control_node } for the modules that were actually placed.
func spawn(module_ids: Array, seed_value: int) -> Dictionary:
	clear()
	var layout := DashboardLayout.place(module_ids, seed_value)
	var placements: Dictionary = layout.get("placements", {})

	for module_id in placements:
		var placement: Dictionary = placements[module_id]
		var slot := _find_slot(placement.get("slot_id", ""))
		if slot == null:
			push_error("ModuleSpawner: scene has no marker for slot '%s'" % placement.get("slot_id", ""))
			continue
		var module_def: Dictionary = ModuleRegistry.def(module_id)
		var node := _instance_into(module_def.get("scene", ""), slot)
		if node == null:
			continue
		_apply_contract(node, module_id, module_def)
		_controls[module_id] = node

	for slot_id in layout.get("empty", []):
		var empty_slot := _find_slot(slot_id)
		if empty_slot != null:
			_instance_into(BLANK_PLATE_SCENE, empty_slot)

	modules_spawned.emit(_controls)
	return _controls

## Push the module's identity and its states from DATA onto the freshly instanced prefab.
##
## The prefab must NOT declare them itself. A .tscn stores literal values and cannot
## reference a script constant (there is no way to write `state_labels = ModuleSwitch.OFF`),
## so any scene-side copy is a second source of truth that no validator can see:
## ModuleRegistry.validate() checks the rules against def()["states"], while the brain
## registers whatever the SCENE carried (flight.gd -> register_control(id, state_labels)).
## Diverge the two and validate() reports clean while the derive silently misbehaves.
## Pushing from here makes the module's data file the only place states are written.
func _apply_contract(node: Node3D, module_id: String, module_def: Dictionary) -> void:
	if not (node is CockpitControl):
		push_error("ModuleSpawner: module '%s' root is not a CockpitControl" % module_id)
		return
	var states: Array = module_def.get("states", [])
	if states.size() < 2:
		push_error("ModuleSpawner: module '%s' declares %d state(s), needs at least 2" % [module_id, states.size()])
	var control := node as CockpitControl
	control.control_id = module_id
	control.state_labels = PackedStringArray(states)

## Slot markers are matched by node NAME, so the scene and DashboardLayout stay in sync
## without a hand-maintained NodePath table.
func _find_slot(slot_id: String) -> Node3D:
	if slot_id.is_empty():
		return null
	return find_child(slot_id, true, false) as Node3D

func _instance_into(scene_path: String, slot: Node3D) -> Node3D:
	if scene_path.is_empty():
		push_error("ModuleSpawner: empty scene path")
		return null
	if not ResourceLoader.exists(scene_path):
		push_error("ModuleSpawner: missing scene '%s'" % scene_path)
		return null
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("ModuleSpawner: could not load '%s'" % scene_path)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		push_error("ModuleSpawner: '%s' root is not a Node3D" % scene_path)
		return null
	slot.add_child(node)
	_spawned.append(node)
	return node

## Every slot marker the scene actually provides, keyed by id — used to check the scene
## against DashboardLayout rather than discovering a missing marker mid-round.
func scene_slot_ids() -> Array:
	var found: Array = []
	for slot in DashboardLayout.slots():
		if _find_slot(slot["id"]) != null:
			found.append(slot["id"])
	return found

## Reports slots DashboardLayout declares but the scene does not provide (and the reverse
## is impossible by construction, since lookup is by declared id). Empty array = in sync.
func validate_scene() -> Array:
	var errors: Array = []
	for slot in DashboardLayout.slots():
		if _find_slot(slot["id"]) == null:
			errors.append("scene missing slot marker '%s'" % slot["id"])
	for anchor_id in DashboardLayout.fact_anchors():
		if find_child(anchor_id, true, false) == null:
			errors.append("scene missing fact anchor '%s'" % anchor_id)
	return errors
