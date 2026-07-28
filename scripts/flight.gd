extends Node3D
class_name FlightRound

## Runs one MISSION: picks the mission from the campaign, spawns exactly its modules onto
## the dashboard, derives the required config through the brain, and validates on LAND.
##
## Difficulty is the mission's own two knobs (which module types, how many) plus the mode's
## pure modifiers. A failed LAND costs a life and NOTHING else — no hidden clock penalty.
## The clock reaching zero is a crash regardless of lives left.
##
## The only round orchestrator. Replaced cockpit_manager.gd (deleted along with its fixed
## three-control cockpit.tscn and the legacy data/manual.gd).

@export var brain_path: NodePath
@export var dashboard_path: NodePath
@export var camera_path: NodePath
@export var status_label_path: NodePath
@export var manual_label_path: NodePath
@export var timer_label_path: NodePath
@export var lives_label_path: NodePath
@export var message_label_path: NodePath
@export var land_button_path: NodePath
## Index into CockpitCampaign.missions(). -1 uses mission_id instead.
@export var mission_index: int = 1
@export var mission_id: String = ""
@export var mode_id: String = CockpitModes.STANDARD
## 0 rolls a fresh seed; anything else reproduces that exact flight (facts AND layout).
@export var fixed_seed: int = 0

var _brain: Node
var _spawner: ModuleSpawner
var _camera: CockpitCameraRig

var _mission: Dictionary = {}
var _controls: Dictionary = {}          # module id -> CockpitControl
var _lives := 1
var _time_left := 0.0
var _playing := false
var _seed := 0

func _ready() -> void:
	get_viewport().physics_object_picking = true

	_brain = get_node_or_null(brain_path)
	_spawner = get_node_or_null(dashboard_path) as ModuleSpawner
	_camera = get_node_or_null(camera_path) as CockpitCameraRig
	if _brain == null or _spawner == null:
		push_error("FlightRound: brain or dashboard missing")
		return

	_mission = _resolve_mission()
	if _mission.is_empty():
		push_error("FlightRound: no mission to run")
		return

	_report_data_errors()

	_seed = fixed_seed if fixed_seed != 0 else int(randi() % 2147483647)
	_lives = CockpitModes.effective_lives(_mission, mode_id)
	_time_left = float(CockpitModes.effective_time(_mission, mode_id))

	_build_dashboard()
	_load_manual()
	_brain.generate_flight(_seed)

	var land_btn := get_node_or_null(land_button_path)
	if land_btn != null and not land_btn.pressed.is_connected(_on_land_pressed):
		land_btn.pressed.connect(_on_land_pressed)

	_playing = true
	print("[flight] mission=%s mode=%s seed=%d lives=%d modules=%s" % [
		_mission.get("id", "?"), mode_id, _seed, _lives, str(_mission.get("modules", []))])
	_refresh_all()

func _resolve_mission() -> Dictionary:
	if not mission_id.is_empty():
		return CockpitCampaign.mission(mission_id)
	return CockpitCampaign.mission_at(mission_index)

## Surface data problems loudly at startup rather than as a silently-wrong round.
func _report_data_errors() -> void:
	for err in ModuleRegistry.validate():
		push_error("ModuleRegistry: " + err)
	for err in CockpitCampaign.validate():
		push_error("CockpitCampaign: " + err)
	for err in DashboardLayout.validate():
		push_error("DashboardLayout: " + err)
	for err in _spawner.validate_scene():
		push_error("Dashboard scene: " + err)

## Spawn the mission's modules, register each with the brain, and tell the camera which
## slots are focusable. Registration MUST happen before the manual loads so the brain can
## resolve state labels and validate the rules against real controls.
func _build_dashboard() -> void:
	_controls = _spawner.spawn(_mission.get("modules", []), _seed)
	var focus_slots: Array = []
	for module_id in _controls:
		var control: CockpitControl = _controls[module_id]
		_brain.register_control(module_id, control.state_labels)
		if not control.cycle_requested.is_connected(_on_cycle_requested):
			control.cycle_requested.connect(_on_cycle_requested)
		control.apply_state(_brain.get_state(module_id))
		var slot := control.get_parent()
		if slot is Node3D:
			focus_slots.append(slot)
	if not _brain.is_connected("state_changed", _on_state_changed):
		_brain.connect("state_changed", _on_state_changed)
	if _camera != null:
		_camera.set_focus_targets(focus_slots)

func _load_manual() -> void:
	var payload := ModuleRegistry.build_manual_data(_mission.get("modules", []))
	var res: String = _brain.load_manual_json(JSON.stringify(payload))
	if res != "OK":
		push_error("FlightRound: manual load failed: %s" % res)

func _process(delta: float) -> void:
	if not _playing:
		return
	_time_left = maxf(0.0, _time_left - delta)
	_refresh_timer()
	if _time_left <= 0.0:
		_finish(false, "TIME UP")

func _on_cycle_requested(id: String) -> void:
	if _playing:
		_brain.request_cycle(id)

func _on_state_changed(id: String, state: int) -> void:
	if _controls.has(id):
		_controls[id].apply_state(state)
	_refresh_status()

func _on_land_pressed() -> void:
	if _playing:
		_attempt_land()

## LAND has three outcomes: LANDED, GO_AROUND (wrong, lives remain), CRASHED.
func _attempt_land() -> void:
	if _brain.is_valid():
		_finish(true, "")
		return
	_lives -= 1
	if _lives <= 0:
		_finish(false, "CRASHED")
		return
	_refresh_lives()
	_set_message(_go_around_text())

## What a failed attempt is allowed to reveal in-round, per the mode. Never names the wrong
## module: with several attempts that collapses into brute force. The recap shows everything.
func _go_around_text() -> String:
	if CockpitModes.feedback(mode_id) == CockpitModes.FEEDBACK_COUNT:
		var wrong := _wrong_count()
		return "GOING AROUND — %d system%s misconfigured." % [wrong, "" if wrong == 1 else "s"]
	return "GOING AROUND — landing aborted."

func _wrong_count() -> int:
	var wrong := 0
	for id in _controls:
		if _brain.has_required(id) and _brain.get_state(id) != _brain.required_state(id):
			wrong += 1
	return wrong

func _finish(success: bool, reason: String) -> void:
	_playing = false
	Game.last_result = {
		"success": success,
		"reason": reason,
		"time_left": _time_left,
		"mission": _mission.get("id", "?"),
		"mode": mode_id,
		"seed": _seed,
		"lives_left": _lives,
		"rows": _debrief_rows(),
	}
	print("[flight] %s (%s)" % ["LANDED" if success else "CRASH", reason])
	Game.goto(Game.ROUND_RECAP)

## Full per-module breakdown. Always computed, shown only on the recap — that is where
## learning happens and it costs nothing.
func _debrief_rows() -> Array:
	var rows: Array = []
	for id in _controls:
		var have: int = _brain.get_state(id)
		var needs_it: bool = _brain.has_required(id)
		rows.append({
			"id": id,
			"you": _brain.state_label(id, have),
			"need": _brain.state_label(id, _brain.required_state(id)) if needs_it else "any",
			"ok": (not needs_it) or have == _brain.required_state(id),
		})
	return rows

# ── HUD ──────────────────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_refresh_manual()
	_refresh_status()
	_refresh_timer()
	_refresh_lives()
	_set_message("")

func _refresh_manual() -> void:
	var lbl := get_node_or_null(manual_label_path)
	if lbl != null:
		lbl.text = "TOWER MANUAL\n" + _brain.manual_text()

func _refresh_status() -> void:
	var lbl := get_node_or_null(status_label_path)
	if lbl == null:
		return
	var facts: Array[String] = []
	for fid in _brain.fact_ids():
		facts.append("  %s: %s" % [fid, _brain.fact_value(fid)])
	var rows: Array[String] = []
	for id in _controls:
		rows.append("  %s: %s" % [id, _brain.state_label(id, _brain.get_state(id))])
	lbl.text = "FLIGHT (read to tower):\n" + "\n".join(facts) + "\n\nCOCKPIT:\n" + "\n".join(rows)

func _refresh_timer() -> void:
	var lbl := get_node_or_null(timer_label_path)
	if lbl != null:
		lbl.text = "T- %02d" % int(ceil(_time_left))

func _refresh_lives() -> void:
	var lbl := get_node_or_null(lives_label_path)
	if lbl != null:
		lbl.text = "GO-AROUNDS LEFT: %d" % maxi(0, _lives - 1)

func _set_message(text: String) -> void:
	var lbl := get_node_or_null(message_label_path)
	if lbl != null:
		lbl.text = text
