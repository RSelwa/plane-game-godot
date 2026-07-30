extends SceneTree

## Gate test for the RUNNING COCKPIT — the half brain_test.gd cannot reach.
## Run headless (no GPU needed; physics and the scene tree are enough):
##   <godot-binary> --headless --path . --script res://scripts/tests/cockpit_test.gd
## Exits 0 on PASS, 1 on FAIL.
##
## brain_test.gd proves the LOGIC. This proves the WIRING between the logic and the scene, which is
## where both bugs of the 30/07 session lived: a lock nobody could open, and wheels that displayed
## a letter the brain had never chosen. Neither was visible from the data layer.
##
## The two invariants worth a test, because breaking either makes a wrong round look like a right
## one — the exact failure this project is built to avoid:
##   FIDELITY    what the cockpit SHOWS == what the brain SAYS. The pilot reads the cockpit aloud;
##               a single stale label sends 18 wrong letters to the tower.
##   THE LOCK    overview click zooms and operates nothing; focused click operates that module only.
##
## It waits FRAMES: Godot defers NOTIFICATION_READY, and the physics space must be stepped once
## before intersect_ray sees any collider.

const WHEEL_LABELS := ["FirstDigit", "SecondDigit", "ThirdDigit"]
const GENERATOR_SAMPLES := 400

var _flight: Node = null
var _frames := 0
var _ok := true

func _initialize() -> void:
	_flight = (load("res://scenes/flight.tscn") as PackedScene).instantiate()
	root.add_child(_flight)

func _check(label: String, got: Variant, want: Variant) -> void:
	var passed: bool = got == want
	if not passed:
		_ok = false
	print("[%s] %s  got=%s want=%s" % ["PASS" if passed else "FAIL", label, got, want])

func _lmb() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	var rig = _flight.get_node_or_null("Camera3D")
	var brain = _flight.get_node_or_null("Brain")
	var dash = _flight.get_node_or_null("Dashboard")
	var spawned: Dictionary = dash.controls()
	_check("the round spawned its modules", spawned.is_empty(), false)
	if spawned.is_empty():
		print("COCKPIT FAIL")
		quit(1)
		return true

	var mid: String = spawned.keys()[0]
	var view: Node3D = spawned[mid]
	var slot: Node3D = view.get_parent()

	_fidelity(brain, view, mid)
	_uniqueness(brain, mid)
	_lock(rig, brain, dash, view, slot, mid)

	print("COCKPIT %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)
	return true

## FIDELITY. Le brain est l'autorité ; la vue doit déjà le refléter AVANT le premier clic. Un
## `set_state` posé avant que `state_changed` soit branché est émis dans le vide, et la molette
## garde le littéral du prefab : c'est exactement le bug « AAA » du 30/07.
func _fidelity(brain, view: Node3D, mid: String) -> void:
	var says := ""
	var shows := ""
	for i in WHEEL_LABELS.size():
		var cid: String = "%s/w%d" % [mid, i]
		says += brain.state_label(cid, brain.get_state(cid))
		shows += (view.get_node(WHEEL_LABELS[i]) as Label3D).text
	_check("cockpit shows what the brain says (before any click)", shows, says)

	## Et après un pas, la vue doit SUIVRE — sinon le pilote lit une lettre périmée.
	var cid0: String = "%s/w0" % mid
	brain.request_cycle(cid0, 1)
	_check("a wheel step repaints its label",
		(view.get_node(WHEEL_LABELS[0]) as Label3D).text,
		brain.state_label(cid0, brain.get_state(cid0)))

## UNIQUENESS. Le module ne tient que si EXACTEMENT un code du pool est épelable : deux, et la tour
## envoie le pilote sur un code faux sans jamais pouvoir le savoir.
func _uniqueness(brain, mid: String) -> void:
	var pool: Array = CockpitFacts.airport_codes()
	var board: Dictionary = brain.module_edgework(mid)
	_check("this round's board spells exactly one pool code",
		_spellable(pool, board["wheels"]), [board["target"]])

	## Le tirage du round est UN échantillon ; l'invariant se vérifie sur beaucoup de plateaux.
	var rng := RandomNumberGenerator.new()
	var broken: Array = []
	for s in GENERATOR_SAMPLES:
		rng.seed = s * 7919 + 13
		var b: Dictionary = ModuleAirportCode.generate(pool, rng)
		if b.is_empty():
			broken.append("seed %d produced no board" % s)
			continue
		var hits := _spellable(pool, b["wheels"])
		if hits != [b["target"]]:
			broken.append("seed %d target=%s spellable=%s" % [s, b["target"], hits])
		if b["start"] == b["target_index"]:
			broken.append("seed %d starts already solved" % s)
	_check("%d generated boards each spell exactly their target" % GENERATOR_SAMPLES, broken, [])

## THE LOCK. En overview le clic CHOISIT, en focus il ACTIONNE — et seulement le module zoomé.
func _lock(rig, brain, dash, view: Node3D, slot: Node3D, mid: String) -> void:
	var cid: String = "%s/w0" % mid

	## Le rayon doit toucher le CENTRE du module : sans corps de visée par slot, seuls les petits
	## boutons répondaient et le verrou ne s'ouvrait jamais.
	_check("a click on the module's centre resolves to its own slot",
		_slot_under(rig, view.global_position), slot.name)

	rig.unfocus()
	_on_focus_cleared(view)
	var before: int = brain.get_state(cid)
	view._on_button_input(null, _lmb(), Vector3.ZERO, Vector3.ZERO, 0, 0, 1)
	_check("overview: the module's buttons are inert", brain.get_state(cid), before)

	rig._focus_under_cursor(rig.unproject_position(view.global_position))
	_check("overview: a click zooms onto the module", rig.is_focused(), true)
	_check("the zoomed module became interactable", view.get("_interactable"), true)

	before = brain.get_state(cid)
	view._on_button_input(null, _lmb(), Vector3.ZERO, Vector3.ZERO, 0, 0, 1)
	_check("focused: a button turns its wheel", brain.get_state(cid) != before, true)

	var held = rig.get("_focused")
	rig._unhandled_input(_lmb())
	_check("focused: a click does not move the camera", rig.get("_focused"), held)

	## Une cellule vide n'est pas une cible : toute la cellule est cliquable, donc sans filtre un
	## clic sur une plaque nue zoomerait sur du vide.
	var empty := _empty_slot(dash, slot)
	rig.unfocus()
	rig.focus_on(empty)
	_check("a blank slot refuses focus (%s)" % empty.name, rig.is_focused(), false)

	## Aucune diaphonie : chaque cellule doit résoudre sur ELLE-MÊME, jamais sur sa voisine.
	var crosstalk: Array = []
	for s in _slot_markers(dash):
		var body := s.get_node_or_null("FocusBody") as Node3D
		if body == null:
			crosstalk.append("%s has no FocusBody" % s.name)
			continue
		var got := _slot_under(rig, body.global_position)
		if got != s.name:
			crosstalk.append("%s -> %s" % [s.name, got])
	_check("every dashboard cell resolves to itself", crosstalk, [])

## Le round câble ça sur focus_changed ; hors round on le refait à la main pour isoler le verrou.
func _on_focus_cleared(view: Node3D) -> void:
	if view.has_method("set_interactable"):
		view.set_interactable(false)

func _spellable(pool: Array, wheels: Array) -> Array:
	var out: Array = []
	for code in pool:
		if ModuleAirportCode.is_spellable(code, wheels):
			out.append(code)
	return out

func _slot_under(rig, world_pos: Vector3) -> String:
	var screen: Vector2 = rig.unproject_position(world_pos)
	var space: PhysicsDirectSpaceState3D = rig.get_world_3d().direct_space_state
	var from: Vector3 = rig.project_ray_origin(screen)
	var params := PhysicsRayQueryParameters3D.create(from, from + rig.project_ray_normal(screen) * 20.0)
	var hit: Dictionary = space.intersect_ray(params)
	if hit.is_empty():
		return "<NOTHING>"
	var slot: Node3D = rig._slot_of(hit["collider"])
	return "<NO SLOT>" if slot == null else str(slot.name)

func _slot_markers(dash) -> Array:
	return dash.find_children("*_r*_c*", "Marker3D", true, false)

func _empty_slot(dash, used: Node3D) -> Node3D:
	for s in _slot_markers(dash):
		if s != used:
			return s
	return null
