extends SceneTree

## SONDE JETABLE — à supprimer. Rejoue la règle d'interaction hors rendu :
##   1. en overview, un clic gauche sur un module le ZOOME
##   2. en overview, les boutons du module IGNORENT ce même clic
##   3. en focus, un clic gauche sur un bouton fait tourner la molette
##   4. en focus, un clic ne redéplace pas la caméra
##   5. un clic sur un slot VIDE ne zoome sur rien
##   6. chaque cellule renvoie SON slot (pas celui du voisin)
##
## Le probe attend des FRAMES : Godot diffère NOTIFICATION_READY, et l'espace physique doit être
## pas-à-pas au moins une fois avant qu'intersect_ray voie quoi que ce soit.

var _flight: Node = null
var _frames := 0
var _ok := true

func _initialize() -> void:
	_flight = (load("res://scenes/flight.tscn") as PackedScene).instantiate()
	root.add_child(_flight)

func _check(label: String, got: Variant, want: Variant) -> void:
	var pass_: bool = got == want
	if not pass_:
		_ok = false
	print("[%s] %s  got=%s want=%s" % ["PASS" if pass_ else "FAIL", label, got, want])

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
	var mid: String = spawned.keys()[0]
	var view: Node3D = spawned[mid]
	var slot: Node3D = view.get_parent()
	print("-- module %s in slot %s --" % [mid, slot.name])

	## Le rayon doit toucher le CENTRE du module, pas seulement ses petits boutons : c'est ce qui
	## rend « cliquer le module » jouable au lieu d'exiger de viser un bouton de 4 cm.
	_check("ray at module centre hits something", _ray_hit_name(rig, view.global_position) != "", true)
	_check("that hit resolves to the module's own slot",
		_ray_slot_name(rig, view.global_position), slot.name)

	# ── 1 + 2. overview : le clic zoome, les boutons l'ignorent ───────────────────────
	var cid: String = "%s/w0" % mid
	var before: int = brain.get_state(cid)
	view._on_button_input(null, _lmb(), Vector3.ZERO, Vector3.ZERO, 0, 0, 1)
	_check("overview: module buttons are inert", brain.get_state(cid), before)

	rig._focus_under_cursor(rig.unproject_position(view.global_position))
	_check("overview: left-click zooms onto the module", rig.is_focused(), true)
	_check("zoomed module became interactable", view.get("_interactable"), true)

	# ── 3. en focus : le bouton agit ──────────────────────────────────────────────────
	before = brain.get_state(cid)
	view._on_button_input(null, _lmb(), Vector3.ZERO, Vector3.ZERO, 0, 0, 1)
	_check("focused: a button turns its wheel", brain.get_state(cid) != before, true)

	# ── 4. en focus : un clic ne redéplace pas la caméra ──────────────────────────────
	var held = rig.get("_focused")
	rig._unhandled_input(_lmb())
	_check("focused: a click does not move the camera", rig.get("_focused"), held)

	# ── 5. un slot VIDE n'est pas focusable ──────────────────────────────────────────
	var empty_slot := _some_empty_slot(dash, slot)
	rig.unfocus()
	rig.focus_on(empty_slot)
	_check("blank slot '%s' refuses focus" % empty_slot.name, rig.is_focused(), false)

	# ── 6. pas de diaphonie entre cellules voisines ───────────────────────────────────
	var crosstalk: Array = []
	for s in dash.find_children("*_r*_c*", "Marker3D", true, false):
		var body := s.get_node_or_null("FocusBody") as Node3D
		if body == null:
			crosstalk.append("%s has no FocusBody" % s.name)
			continue
		var name_hit := _ray_slot_name(rig, body.global_position)
		if name_hit != s.name:
			crosstalk.append("%s -> %s" % [s.name, name_hit])
	_check("every cell resolves to itself (%d cells)" % 12, crosstalk, [])

	print("PROBE %s" % ["PASS" if _ok else "FAIL"])
	quit(0 if _ok else 1)
	return true

func _ray_hit_name(rig, world_pos: Vector3) -> String:
	var screen: Vector2 = rig.unproject_position(world_pos)
	var space: PhysicsDirectSpaceState3D = rig.get_world_3d().direct_space_state
	var from: Vector3 = rig.project_ray_origin(screen)
	var params := PhysicsRayQueryParameters3D.create(from, from + rig.project_ray_normal(screen) * 20.0)
	var hit: Dictionary = space.intersect_ray(params)
	return "" if hit.is_empty() else str(hit["collider"].name)

func _ray_slot_name(rig, world_pos: Vector3) -> String:
	var screen: Vector2 = rig.unproject_position(world_pos)
	var space: PhysicsDirectSpaceState3D = rig.get_world_3d().direct_space_state
	var from: Vector3 = rig.project_ray_origin(screen)
	var params := PhysicsRayQueryParameters3D.create(from, from + rig.project_ray_normal(screen) * 20.0)
	var hit: Dictionary = space.intersect_ray(params)
	if hit.is_empty():
		return "<NOTHING>"
	var slot: Node3D = rig._slot_of(hit["collider"])
	return "<NO SLOT>" if slot == null else str(slot.name)

func _some_empty_slot(dash, used: Node3D) -> Node3D:
	for s in dash.find_children("*_r*_c*", "Marker3D", true, false):
		if s != used:
			return s
	return null
