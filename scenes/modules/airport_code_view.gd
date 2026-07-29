extends Node3D

## VUE du module AIRPORT CODE — trois molettes de lettres.
##
## Elle ne possède AUCUN état : un clic sur ± demande un pas au round, le brain décide, et
## `apply_control_state` revient dessiner le résultat. Même contrat que CockpitControl, mais en
## N exemplaires — un module, trois controls (CLAUDE.md, « 1 module = N controls »).
##
## Elle ne reçoit JAMAIS la réponse. `bind_wheels` ne lui passe que les lettres ; `target` et
## `target_index` restent dans le brain. En multijoueur cette vue sera côté client, donc tout ce
## qui passe par elle est trichable.

signal cycle_requested(id: String, step: int)

## L'ordre EST celui des molettes : index 0 = première lettre du code. Si le modèle apparaît
## inversé dans le cockpit, c'est cette liste qu'on retourne — jamais la géométrie.
const LABEL_NODES := ["FirstDigit", "SecondDigit", "ThirdDigit"]
const MINUS_NODES := ["Buttons/Digit1Minus", "Buttons/Digit2Minus", "Buttons/Digit3Minus"]
const PLUS_NODES := ["Buttons/Digit1Plus", "Buttons/Digit2Plus", "Buttons/Digit3Plus"]

var _control_ids: Array = []
var _wheels: Array = []
var _index_of: Dictionary = {}          # control id -> index de molette
var _buttons_connected := false

## Appelée par FlightRound juste après le tirage du plateau. `wheels[i]` = les lettres de la
## molette i, dans l'ordre où ses états sont indexés côté brain : l'état 2 du control, c'est
## `wheels[i][2]`. C'est ce qui permet à la vue de dessiner sans redemander au brain.
func bind_wheels(control_ids: Array, wheels: Array) -> void:
	_control_ids = control_ids.duplicate()
	_wheels = wheels.duplicate(true)
	_index_of.clear()
	for i in _control_ids.size():
		_index_of[_control_ids[i]] = i
	_connect_buttons()

## Dessine l'état d'UNE molette. Le round passe l'id du control parce que la vue en porte
## plusieurs — sans lui elle ne saurait pas laquelle redessiner.
func apply_control_state(control_id: String, state: int) -> void:
	if not _index_of.has(control_id):
		return
	var i: int = _index_of[control_id]
	if i >= LABEL_NODES.size() or i >= _wheels.size():
		return
	var lbl := get_node_or_null(LABEL_NODES[i]) as Label3D
	if lbl == null:
		push_error("AirportCode: Label3D '%s' introuvable" % LABEL_NODES[i])
		return
	var letters: Array = _wheels[i]
	lbl.text = str(letters[state]) if state >= 0 and state < letters.size() else "?"

## Un StaticBody3D ne clique pas tout seul : il faut brancher `input_event`, et le viewport doit
## avoir `physics_object_picking` (posé par FlightRound._ready).
func _connect_buttons() -> void:
	if _buttons_connected:
		return
	_buttons_connected = true
	for i in mini(_control_ids.size(), LABEL_NODES.size()):
		_connect_button(MINUS_NODES[i], i, -1)
		_connect_button(PLUS_NODES[i], i, 1)

## `bind()` fige la molette et le pas dans la Callable, donc les 6 boutons partagent un seul
## handler au lieu de six méthodes copiées.
func _connect_button(path: String, wheel: int, step: int) -> void:
	var body := get_node_or_null(path) as StaticBody3D
	if body == null:
		push_error("AirportCode: bouton '%s' introuvable" % path)
		return
	body.input_event.connect(_on_button_input.bind(wheel, step))

func _on_button_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3,
		_shape: int, wheel: int, step: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if wheel < _control_ids.size():
		cycle_requested.emit(_control_ids[wheel], step)
