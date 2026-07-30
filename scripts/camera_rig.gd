extends Camera3D
class_name CockpitCameraRig

## Two-tier cockpit camera.
##
## OVERVIEW: a seated free-look clamped in pitch and yaw. The pilot glances UP to read the
## overhead zone and loses sight of the main panel doing it — that glance is the tension.
## FOCUS: the camera tweens to a slot's FocusPoint so one module is readable. It is a camera
## move in 3D, never a UI modal: the neighbours stay on screen and the HUD stays up, because
## losing peripheral awareness would kill the panic.
##
## Every binding goes through an InputMap ACTION, never a raw key or button: adding a gamepad
## (or letting the player rebind) is then a bind in project.godot, not a change here.
##   camera_look (RMB, hold)  = free-look; a click with no drag focuses the module under the cursor
##   cam_look_* (right stick)  = free-look on a pad
##   focus_next / focus_prev   = cycle focus (TAB / bumpers) -- swings the head too
##   back (ESC / B)            = leave focus
##   interact (LMB / A)        = operate a control -- consumed by the control, not here
## Exiting focus restores the look direction the pilot had, never a reset pose.

signal focus_changed(slot: Node3D)

@export var eye_path: NodePath
@export var pitch_min_deg: float = -25.0
@export var pitch_max_deg: float = 35.0
@export var yaw_limit_deg: float = 35.0
@export var look_sensitivity: float = 0.18
## Right-stick look speed, in degrees per second at full deflection.
@export var stick_sensitivity: float = 140.0
@export var focus_time: float = 0.3
## A right-press that travels further than this many pixels counts as a look-drag, not a click.
@export var click_slop_px: float = 6.0

var _eye := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0

var _looking := false
var _drag_px := 0.0

var _focused: Node3D = null
var _focus_targets: Array[Node3D] = []
var _focus_index := -1

var _tween: Tween
var _tween_from := Transform3D.IDENTITY
var _tween_to := Transform3D.IDENTITY

func _ready() -> void:
	var eye := get_node_or_null(eye_path)
	if eye is Node3D:
		_eye = (eye as Node3D).global_position
	else:
		_eye = global_position
	_apply_overview()

## Slots the pilot may focus, in dashboard order. Pass the slot markers that actually got a
## module; blank plates are deliberately not focusable.
func set_focus_targets(targets: Array) -> void:
	_focus_targets.clear()
	for t in targets:
		if t is Node3D:
			_focus_targets.append(t)
	_focus_index = -1

func is_focused() -> bool:
	return _focused != null

# ── Input ────────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_look"):
		_looking = true
		_drag_px = 0.0
		return
	if event.is_action_released("camera_look"):
		_looking = false
		if _drag_px <= click_slop_px and event is InputEventMouseButton:
			_focus_under_cursor((event as InputEventMouseButton).position)
		return

	if event is InputEventMouseMotion and _looking and not is_focused():
		_drag_px += event.relative.length()
		_yaw = clampf(_yaw - event.relative.x * look_sensitivity, -yaw_limit_deg, yaw_limit_deg)
		_pitch = clampf(_pitch - event.relative.y * look_sensitivity, pitch_min_deg, pitch_max_deg)
		_apply_overview()
		return

	if event is InputEventMouseMotion and _looking:
		_drag_px += event.relative.length()
		return

	if event.is_action_pressed("focus_next"):
		_cycle_focus(1)
	elif event.is_action_pressed("focus_prev"):
		_cycle_focus(-1)
	elif event.is_action_pressed("back"):
		unfocus()

## Right-stick free-look: analog, so it lives in _process rather than reacting to one event.
## Same clamps and same disable-while-focused rule as the mouse.
func _process(delta: float) -> void:
	if is_focused():
		return
	var look := Input.get_vector("cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down")
	if look == Vector2.ZERO:
		return
	_yaw = clampf(_yaw - look.x * stick_sensitivity * delta, -yaw_limit_deg, yaw_limit_deg)
	_pitch = clampf(_pitch - look.y * stick_sensitivity * delta, pitch_min_deg, pitch_max_deg)
	_apply_overview()

# ── Focus ────────────────────────────────────────────────────────────────────────────

func _cycle_focus(dir: int) -> void:
	if _focus_targets.is_empty():
		return
	var n := _focus_targets.size()
	_focus_index = ((_focus_index + dir) % n + n) % n
	focus_on(_focus_targets[_focus_index])

func _focus_under_cursor(screen_pos: Vector2) -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		project_ray_origin(screen_pos),
		project_ray_origin(screen_pos) + project_ray_normal(screen_pos) * 20.0)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return
	var slot := _slot_of(hit.get("collider"))
	if slot != null:
		_focus_index = _focus_targets.find(slot)
		focus_on(slot)

## Walk up from whatever the ray hit to the slot marker that owns it.
func _slot_of(node: Variant) -> Node3D:
	var n := node as Node
	while n != null:
		if n is Node3D and n.has_node("FocusPoint"):
			return n as Node3D
		n = n.get_parent()
	return null

func focus_on(slot: Node3D) -> void:
	if slot == null:
		return
	var point := slot.get_node_or_null("FocusPoint") as Node3D
	if point == null:
		push_error("CockpitCameraRig: slot '%s' has no FocusPoint" % slot.name)
		return
	_focused = slot
	_tween_to_transform(point.global_transform)
	focus_changed.emit(slot)

## Back to overview, restoring the look direction the pilot had before focusing.
func unfocus() -> void:
	if _focused == null:
		return
	_focused = null
	_tween_to_transform(_overview_transform())
	focus_changed.emit(null)

# ── Transforms ───────────────────────────────────────────────────────────────────────

func _overview_transform() -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0))
	return Transform3D(basis, _eye)

func _apply_overview() -> void:
	if is_focused():
		return
	global_transform = _overview_transform()

func _tween_to_transform(target: Transform3D) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween_from = global_transform
	_tween_to = target
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_tween_progress, 0.0, 1.0, focus_time)

func _set_tween_progress(t: float) -> void:
	global_transform = _tween_from.interpolate_with(_tween_to, t)
