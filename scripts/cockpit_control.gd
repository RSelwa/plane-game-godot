extends StaticBody3D
class_name CockpitControl

## VIEW for one cockpit control (switch / lever / dial). It owns NO canonical
## state: a click just emits `cycle_requested`; the CockpitManager forwards it to
## the authoritative C# CockpitBrain, and the brain tells us the new state to draw
## via `apply_state`. Keeping the visual a pure function of state means any peer
## (later, in multiplayer) can render it from replicated state.

## `step` est toujours +1 ici : un interrupteur ne tourne que dans un sens. Le paramètre existe
## pour que TOUS les controls émettent la même forme de signal — une molette de lettres a un
## bouton − autant qu'un +, et le round ne veut pas deux handlers pour la même intention.
signal cycle_requested(id: String, step: int)

## Identity and states are NOT authored here or in the prefab — ModuleSpawner pushes them
## from the module's data file at spawn time, which keeps data/modules/<id>.gd the only place
## they are written. Defaults are deliberately EMPTY so a module that was never pushed fails
## loudly (the brain rejects an unknown control id) instead of silently behaving like a
## two-state OFF/ON switch.
@export var control_id: String = ""
@export var state_labels: PackedStringArray = PackedStringArray()
@export var handle_path: NodePath
@export var min_angle_deg: float = -35.0
@export var max_angle_deg: float = 35.0

## A control only takes input once the camera is FOCUSED on its module: in overview a click
## just picks a module to zoom into, it never operates it. The round sets this from the
## camera's focus_changed, so the authority over "which module is live" stays in one place.
var _interactable := false

func set_interactable(value: bool) -> void:
	_interactable = value

func _ready() -> void:
	input_event.connect(_on_input_event)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if not _interactable:
		return
	if event.is_action_pressed("interact"):
		cycle_requested.emit(control_id, 1)

## Draw the given canonical state. Called by the manager after the brain updates.
func apply_state(state: int) -> void:
	if handle_path.is_empty():
		return
	var handle := get_node_or_null(handle_path)
	if handle == null:
		return
	var n := state_labels.size()
	var t := 0.0 if n <= 1 else float(state) / float(n - 1)
	handle.rotation_degrees.x = lerpf(min_angle_deg, max_angle_deg, t)
