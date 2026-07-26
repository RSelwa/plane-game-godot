extends StaticBody3D
class_name CockpitControl

## VIEW for one cockpit control (switch / lever / dial). It owns NO canonical
## state: a click just emits `cycle_requested`; the CockpitManager forwards it to
## the authoritative C# CockpitBrain, and the brain tells us the new state to draw
## via `apply_state`. Keeping the visual a pure function of state means any peer
## (later, in multiplayer) can render it from replicated state.

signal cycle_requested(id: String)

@export var control_id: String = "control"
@export var state_labels: PackedStringArray = PackedStringArray(["OFF", "ON"])
@export var handle_path: NodePath
@export var min_angle_deg: float = -35.0
@export var max_angle_deg: float = 35.0

func _ready() -> void:
	input_event.connect(_on_input_event)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cycle_requested.emit(control_id)

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
