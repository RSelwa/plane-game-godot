extends Node3D
class_name FlightRound

## Runs one ROUND: resolves the round's module list, spawns exactly those modules onto
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
@export var mode_id: String = CockpitModes.STANDARD
## 0 rolls a fresh seed; anything else reproduces that exact flight (facts AND layout).
@export var fixed_seed: int = 0

## Typé, pas `Node` : sinon chaque appel `_brain.xxx()` retourne du Variant, `:=` n'a rien à
## inférer, et une méthode mal orthographiée ne se voit qu'à l'exécution.
var _brain: CockpitBrain
var _spawner: ModuleSpawner
var _camera: CockpitCameraRig

var _mission: Mission = null
## Un module peut porter PLUSIEURS controls (un module à molettes en a un par molette), donc
## deux tables au lieu d'une : ce qui a été spawné, et qui dessine quoi.
var _modules: Dictionary = {} # module id -> le nœud spawné (Node3D)
var _control_owner: Dictionary = {} # control id -> le nœud qui le DESSINE
var _control_module: Dictionary = {} # control id -> le module qui le PORTE (pour le verrou)
var _lives := 1
var _time_left := 0.0
var _playing := false
var _seed := 0
## Le debug est le SEUL endroit du jeu qui MONTRE la réponse, donc caché par défaut. Il lit tout
## depuis le brain, jamais depuis la vue : au multijoueur le brain sera côté serveur, et une
## réponse qui aurait transité par le client serait trichable.
var _debug_visible := false

func _ready() -> void:
	get_viewport().physics_object_picking = true

	_brain = get_node_or_null(brain_path) as CockpitBrain
	_spawner = get_node_or_null(dashboard_path) as ModuleSpawner
	_camera = get_node_or_null(camera_path) as CockpitCameraRig
	if _brain == null or _spawner == null:
		push_error("FlightRound: brain or dashboard missing")
		return

	_mission = _resolve_mission()
	if _mission == null:
		push_error("FlightRound: no mission to run")
		return

	_report_data_errors()

	_seed = fixed_seed if fixed_seed != 0 else int(randi() % 2147483647)
	_lives = CockpitModes.effective_lives(_mission, mode_id)
	_time_left = float(CockpitModes.effective_time(_mission, mode_id))

	_build_dashboard()
	_load_manual()
	_brain.generate_flight(_seed)
	_apply_module_answers()

	var land_btn := get_node_or_null(land_button_path)
	if land_btn != null and not land_btn.pressed.is_connected(_on_land_pressed):
		land_btn.pressed.connect(_on_land_pressed)

	_playing = true
	print("[flight] mission=%s mode=%s seed=%d lives=%d modules=%s" % [
		_mission.id, mode_id, _seed, _lives, str(_mission.modules)])
	_refresh_all()

func _resolve_mission() -> Mission:
	var mods: Array[ModuleInstance] = [ModuleInstance.new("airport_code_1", ModuleAirportCode.ID)]
	return Mission.new("dev_airport_code", mods, 180, 2)

## Surface data problems loudly at startup rather than as a silently-wrong round.
func _report_data_errors() -> void:
	for err in ModuleRegistry.validate():
		push_error("ModuleRegistry: " + err)
	for err in DashboardLayout.validate():
		push_error("DashboardLayout: " + err)
	for err in _spawner.validate_scene():
		push_error("Dashboard scene: " + err)

## Spawn the mission's modules, register each with the brain, and tell the camera which
## slots are focusable. Registration MUST happen before the manual loads so the brain can
## resolve state labels and validate the rules against real controls.
func _build_dashboard() -> void:
	_modules = _spawner.spawn(_mission.modules, _seed)
	_control_owner.clear()
	_control_module.clear()
	## UN SEUL flux rng pour tout le tableau de bord : chaque instance avance le flux, donc deux
	## instances du même type tirent des plateaux différents, et la seed reproduit l'ensemble.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var focus_slots: Array = []
	## On itère les INSTANCES de la mission, pas la table de spawn : c'est là que vivent les deux
	## ids. `inst.id` clé tout (brain, controls, verrou, lampe), `inst.type` ne sert qu'à retrouver
	## la fiche et à tirer l'edgework. Ordre = ordre de la mission, donc déterministe.
	for inst in _mission.modules:
		if not _modules.has(inst.id):
			continue  ## non placé / prefab manquant — le spawner a déjà crié
		var node: Node3D = _modules[inst.id]
		_brain.register_module(inst.id, inst.type)
		var d := ModuleRegistry.def(inst.type)
		if d.get("kind", ModuleRegistry.KIND_STATES) == ModuleRegistry.KIND_WHEELS:
			_register_wheels_module(inst.id, inst.type, node, rng)
		else:
			_register_control_module(inst.id, node)
		var slot := node.get_parent()
		if slot is Node3D:
			focus_slots.append(slot)
	if not _brain.is_connected("state_changed", _on_state_changed):
		_brain.connect("state_changed", _on_state_changed)
	if not _brain.is_connected("module_status_changed", _on_module_status_changed):
		_brain.connect("module_status_changed", _on_module_status_changed)
	if _camera != null:
		if not _camera.focus_changed.is_connected(_on_focus_changed):
			_camera.focus_changed.connect(_on_focus_changed)
		_camera.set_focus_targets(focus_slots)
		_on_focus_changed(null)

## Only the module the camera is focused on may be operated; overview clicks just pick a
## module to zoom. Passing null (overview / unfocus) makes every module inert.
func _on_focus_changed(slot: Node3D) -> void:
	for module_id in _modules:
		var node: Node3D = _modules[module_id]
		if node.has_method("set_interactable"):
			node.set_interactable(node.get_parent() == slot)

## Module à état unique : le prefab EST le control, son id est celui de l'INSTANCE (le spawner
## l'a poussé dessus). Aucun besoin du type ici — la fiche a déjà servi au spawn.
func _register_control_module(module_id: String, node: Node3D) -> void:
	var control := node as CockpitControl
	if control == null:
		push_error("FlightRound: module '%s' root is not a CockpitControl" % module_id)
		return
	_brain.register_control(module_id, control.state_labels)
	_brain.set_module_controls(module_id, [module_id])
	_control_owner[module_id] = control
	_control_module[module_id] = module_id
	if not control.cycle_requested.is_connected(_on_cycle_requested):
		control.cycle_requested.connect(_on_cycle_requested)
	control.apply_state(_brain.get_state(module_id))

## Module à molettes : UN control par molette, dont les ÉTATS sont les lettres tirées de la
## seed. C'est ici que « 1 module = N controls » se produit réellement.
##
## SEUL endroit qui a besoin des DEUX ids : `type` choisit l'algorithme de tirage (la fiche),
## `module_id` clé le résultat. Deux exemplaires du même type passent donc ici avec le même
## `type` et deux `module_id` différents — même stratégie, deux plateaux (Modèle B).
func _register_wheels_module(module_id: String, type: String, node: Node3D, rng: RandomNumberGenerator) -> void:
	var board := ModuleRegistry.roll_edgework(type, rng)
	if board.is_empty():
		push_error("FlightRound: module '%s' produced no board" % module_id)
		return
	_brain.set_module_edgework(module_id, board)
	var wheels: Array = board["wheels"]
	var start: Array = board["start"]
	var ids: Array[String] = []
	for i in wheels.size():
		var cid := ModuleRegistry.wheel_control_id(module_id, i)
		_brain.register_control(cid, wheels[i])
		_control_owner[cid] = node
		_control_module[cid] = module_id
		ids.append(cid)
	_brain.set_module_controls(module_id, ids)
	## La vue ne reçoit QUE ce que le pilote peut voir : les lettres. `target` / `target_index`
	## restent dans le brain — en multijoueur la vue sera côté client, donc trichable.
	if node.has_method("bind_wheels"):
		node.bind_wheels(module_id, ids, wheels)
	if node.has_signal("cycle_requested") and not node.cycle_requested.is_connected(_on_cycle_requested):
		node.cycle_requested.connect(_on_cycle_requested)
	if node.has_signal("submit_requested") and not node.submit_requested.is_connected(_on_submit_requested):
		node.submit_requested.connect(_on_submit_requested)
	## Rotation de départ posée APRÈS le bind, pour que la vue reçoive bien le signal.
	for i in ids.size():
		_brain.set_state(ids[i], int(start[i]))

## Les réponses des modules générés, posées APRÈS generate_flight — lui appelle clear_required()
## et effacerait tout ce qui aurait été posé avant.
func _apply_module_answers() -> void:
	for module_id in _modules:
		var board: Dictionary = _brain.module_edgework(module_id)
		var target_index: Array = board.get("target_index", [])
		for i in target_index.size():
			_brain.set_required(ModuleRegistry.wheel_control_id(module_id, i), int(target_index[i]))

func _load_manual() -> void:
	var payload := ModuleRegistry.build_manual_data(_mission.modules)
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

func _on_cycle_requested(id: String, step: int) -> void:
	if not _playing:
		return
	## Un module validé est VERROUILLÉ. Le verrou est vérifié ICI et pas dans la vue : une vue qui
	## refuse d'émettre suffit en solo, mais en multijoueur elle sera côté client. L'autorité doit
	## rester du côté qui connaît la réponse.
	var module_id: String = _control_module.get(id, "")
	if not module_id.is_empty() and _brain.module_correct(module_id):
		return
	_brain.request_cycle(id, step)
	## Bouger une molette éteint le rouge : ainsi « rouge » veut dire « CETTE combinaison a été
	## refusée » et pas « tu t'es trompé à un moment ». Aucune information de plus n'est donnée —
	## il faut toujours un Submit pour apprendre quoi que ce soit — mais ça évite de re-soumettre
	## deux fois le même code.
	if not module_id.is_empty() and _brain.module_status(module_id) != null:
		_brain.reset_module(module_id)

## Submit sur un module : le BRAIN juge, la vue ne fait que demander. Un module déjà validé ne se
## re-soumet pas — sinon la lampe verte pourrait repasser au rouge sans qu'une molette ait bougé.
func _on_submit_requested(module_id: String) -> void:
	if not _playing or _brain.module_correct(module_id):
		return
	var ok: bool = _brain.module_matches_required(module_id)
	_brain.mark_module(module_id, ModuleStore.CORRECT if ok else ModuleStore.WRONG)

## Le statut d'un module a changé → sa lampe. Le round route, il ne décide pas de la couleur :
## c'est la vue du module qui sait à quoi ressemble SON retour d'information.
func _on_module_status_changed(module_id: String, status) -> void:
	var node = _modules.get(module_id)
	if node != null and node.has_method("apply_module_status"):
		node.apply_module_status(status)

## Le brain a changé un état : on le fait dessiner par le nœud qui possède ce control. Un
## module à molettes reçoit l'id du control, sinon il ne saurait pas QUELLE molette redessiner.
func _on_state_changed(id: String, state: int) -> void:
	if _control_owner.has(id):
		var view = _control_owner[id]
		if view.has_method("apply_control_state"):
			view.apply_control_state(id, state)
		elif view is CockpitControl:
			(view as CockpitControl).apply_state(state)
	_refresh_status()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_debug_visible = not _debug_visible
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
	for id in _control_owner:
		if _brain.has_required(id) and _brain.get_state(id) != _brain.required_state(id):
			wrong += 1
	return wrong

func _finish(success: bool, reason: String) -> void:
	_playing = false
	Game.last_result = {
		"success": success,
		"reason": reason,
		"time_left": _time_left,
		"mission": _mission.id,
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
	for id in _control_owner:
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
	for id in _control_owner:
		rows.append("  %s: %s" % [id, _brain.state_label(id, _brain.get_state(id))])
	lbl.text = "SEED: %d\n\nFLIGHT (read to tower):\n" % _seed + "\n".join(facts) \
		+"\n\nCOCKPIT:\n" + "\n".join(rows) + _debug_text()

## Le plateau et la réponse de chaque module généré. Caché derrière F3 : c'est la solution.
## Tout vient du brain — le spawner et les vues ne sont jamais interrogés.
func _debug_text() -> String:
	if not _debug_visible:
		return "\n\n[F3] debug"
	var out: Array[String] = ["", "── DEBUG (F3) ──"]
	for module_id in _modules:
		var board: Dictionary = _brain.module_edgework(module_id)
		if board.is_empty():
			continue
		var wheels: Array = board.get("wheels", [])
		var target_index: Array = board.get("target_index", [])
		out.append("%s   target=%s" % [module_id, board.get("target", "?")])
		var typed := ""
		for i in wheels.size():
			var cid := ModuleRegistry.wheel_control_id(module_id, i)
			var current: String = _brain.state_label(cid, _brain.get_state(cid))
			typed += current
			var letters := PackedStringArray(wheels[i])
			var need := "?"
			if i < target_index.size():
				need = str(wheels[i][int(target_index[i])])
			out.append("  w%d [%s]  need=%s  is=%s" % [i, " ".join(letters), need, current])
		out.append("  composé=%s  valide=%s" % [typed, str(_brain.module_matches_required(module_id))])
	return "\n".join(out)

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
