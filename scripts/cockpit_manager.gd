extends Node3D
class_name CockpitManager

## Runs one landing round as an information-asymmetry puzzle. The PILOT reads cues (a
## warning-light colour, a system code) they can't interpret; the TOWER holds a static
## rulebook (loaded from data/manual.gd). Each round the C# CockpitBrain rolls the cues
## and DERIVES the required config from the rules — never shown, only looked up. On LAND
## (or timeout) the brain validates, and we hand a result snapshot to the recap scene.

@export var brain_path: NodePath
@export var status_label_path: NodePath
@export var manual_label_path: NodePath
@export var timer_label_path: NodePath
@export var land_button_path: NodePath
@export var warn_light_path: NodePath
@export var round_seconds: float = 60.0
## Solo dev aid: show OK/... correctness on the pilot panel. OFF for the real puzzle.
@export var show_correctness_debug: bool = false

const _REQUIRED_METHODS := [
	"RegisterControl", "RequestCycle", "GetState", "IsValid", "StateLabel", "NumStates",
	"LoadManualJson", "GenerateFlight", "ManualText", "FactIds", "FactValue",
	"HasRequired", "RequiredState",
]
const _WARN_COLORS := {
	"GREEN": Color(0.2, 0.9, 0.3),
	"AMBER": Color(1.0, 0.7, 0.1),
	"RED": Color(1.0, 0.2, 0.2),
}

var _brain: Node
var _controls: Dictionary = {}  # id (String) -> CockpitControl
var _time_left: float = 0.0
var _playing: bool = false

func _ready() -> void:
	get_viewport().physics_object_picking = true
	_brain = get_node_or_null(brain_path)
	if _brain == null:
		push_error("CockpitManager: brain not found at '%s'" % brain_path)
		return
	for m in _REQUIRED_METHODS:
		if not _brain.has_method(m):
			push_error("CockpitManager: brain missing method '%s'" % m)
	if not _brain.has_signal("StateChanged"):
		push_error("CockpitManager: brain missing signal 'StateChanged'")
	_brain.connect("StateChanged", _on_state_changed)
	for c in find_children("*", "CockpitControl", true, false):
		if _controls.has(c.control_id):
			push_error("CockpitManager: duplicate control id '%s'" % c.control_id)
			continue
		_controls[c.control_id] = c
		_brain.RegisterControl(c.control_id, c.state_labels)
		c.cycle_requested.connect(_on_cycle_requested)
		c.apply_state(_brain.GetState(c.control_id))
	_load_manual()
	var land_btn := get_node_or_null(land_button_path)
	if land_btn and not land_btn.pressed.is_connected(_on_land_pressed):
		land_btn.pressed.connect(_on_land_pressed)
	_start_round()

## Load the tower manual from the data module (data/manual.gd). Controls must be
## registered first so the brain can resolve state labels and validate the rules.
func _load_manual() -> void:
	var json := JSON.stringify(CockpitManual.data())
	var res: String = _brain.LoadManualJson(json)
	if res != "OK":
		push_error("CockpitManual load failed: %s" % res)

func _start_round() -> void:
	var round_seed := int(randi() % 2147483647)
	_brain.GenerateFlight(round_seed)
	_time_left = round_seconds
	_playing = true
	_apply_warn_light()
	print("[round] seed=%d WARN=%s from=%s to=%s flight=%s" % [round_seed,
		_brain.FactValue("WARN"), _brain.FactValue("starting_airport"),
		_brain.FactValue("arriving_airport"), _brain.FactValue("flight_number")])
	_refresh_manual()
	_refresh_status()
	_refresh_timer()

func _process(delta: float) -> void:
	if not _playing:
		return
	_time_left = maxf(0.0, _time_left - delta)
	_refresh_timer()
	if _time_left <= 0.0:
		_attempt_land(true)

func _on_cycle_requested(id: String) -> void:
	if _playing:
		_brain.RequestCycle(id)

func _on_state_changed(id: String, state: int) -> void:
	if _controls.has(id):
		_controls[id].apply_state(state)
	_refresh_status()

func _on_land_pressed() -> void:
	if _playing:
		_attempt_land(false)

func _attempt_land(timed_out: bool) -> void:
	_playing = false
	var ok: bool = _brain.IsValid()
	# Snapshot a debrief (what the pilot set vs what the manual required) for the recap.
	var rows: Array = []
	for id in _controls:
		var have: int = _brain.GetState(id)
		var needs_it: bool = _brain.HasRequired(id)
		rows.append({
			"id": id,
			"you": _brain.StateLabel(id, have),
			"need": _brain.StateLabel(id, _brain.RequiredState(id)) if needs_it else "any",
			"ok": (not needs_it) or have == _brain.RequiredState(id),
		})
	Game.last_result = {
		"success": ok,
		"reason": ("TIME UP" if timed_out else "") if not ok else "",
		"time_left": _time_left,
		"rows": rows,
	}
	print("[round] LAND (timeout=%s) -> %s" % [timed_out, "SUCCESS" if ok else "CRASH"])
	Game.goto(Game.ROUND_RECAP)

func _apply_warn_light() -> void:
	var wl := get_node_or_null(warn_light_path)
	if wl == null:
		return
	var col: Color = _WARN_COLORS.get(_brain.FactValue("WARN"), Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.5
	wl.material_override = mat

func _refresh_manual() -> void:
	var lbl := get_node_or_null(manual_label_path)
	if lbl == null:
		return
	lbl.text = "TOWER MANUAL\n" + _brain.ManualText()

func _refresh_status() -> void:
	var lbl := get_node_or_null(status_label_path)
	if lbl == null:
		return
	var facts: Array[String] = []
	for fid in _brain.FactIds():
		facts.append("  %s: %s" % [fid, _brain.FactValue(fid)])
	var rows: Array[String] = []
	for id in _controls:
		var st: int = _brain.GetState(id)
		var mark := ""
		if show_correctness_debug and _brain.HasRequired(id):
			mark = "  OK" if st == _brain.RequiredState(id) else "  ..."
		rows.append("  %s: %s%s" % [id, _brain.StateLabel(id, st), mark])
	lbl.text = "FLIGHT (read to tower):\n" + "\n".join(facts) + "\n\nCOCKPIT:\n" + "\n".join(rows)

func _refresh_timer() -> void:
	var lbl := get_node_or_null(timer_label_path)
	if lbl == null:
		return
	lbl.text = "T- %02d" % int(ceil(_time_left))
