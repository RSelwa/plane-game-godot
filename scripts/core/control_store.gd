extends RefCounted
class_name ControlStore

## Owns every control's labels, current state, and derived required state. Pure logic,
## id-keyed: the same handful of methods serve any number of controls. Emits nothing --
## the facade (CockpitBrain) turns state changes into signals.

var _labels: Dictionary = {}
var _order: Array = []
var _state: Dictionary = {}
var _required: Dictionary = {}

func register_control(id: String, state_labels) -> void:
	if id.is_empty():
		push_error("CockpitBrain: empty control id ignored.")
		return
	if _labels.has(id):
		push_error("CockpitBrain: duplicate control id '%s' ignored." % id)
		return
	var src: Array = []
	if state_labels != null:
		for s in state_labels:
			src.append(str(s))
	var n := maxi(1, src.size())
	var labels: Array = []
	for i in n:
		labels.append(src[i] if i < src.size() else str(i))
	_labels[id] = labels
	_order.append(id)
	_state[id] = 0

func has(id: String) -> bool:
	return _labels.has(id)

func num_states(id: String) -> int:
	return (_labels[id] as Array).size() if _labels.has(id) else 0

func get_state(id: String) -> int:
	return _state.get(id, -1)

func state_label(id: String, state: int) -> String:
	if not _labels.has(id):
		return "?"
	var l: Array = _labels[id]
	return l[state] if state >= 0 and state < l.size() else "?"

func label_index(id: String, label: String) -> int:
	if not _labels.has(id):
		return -1
	var l: Array = _labels[id]
	for i in l.size():
		if l[i] == label:
			return i
	return -1

func request_cycle(id: String) -> int:
	if not _state.has(id):
		push_error("CockpitBrain: cycle unknown control '%s'." % id)
		return -1
	var n: int = (_labels[id] as Array).size()
	var s := (int(_state[id]) + 1) % n
	_state[id] = s
	return s

func set_state(id: String, state: int) -> int:
	if not _state.has(id):
		return -1
	var n: int = (_labels[id] as Array).size()
	_state[id] = ((state % n) + n) % n
	return _state[id]

func set_required(id: String, state: int) -> void:
	_required[id] = state

func clear_required() -> void:
	_required.clear()

func has_required(id: String) -> bool:
	return _required.has(id)

func required_state(id: String) -> int:
	return _required.get(id, -1)

func is_valid() -> bool:
	for id in _required:
		if not _state.has(id):
			return false
		if int(_state[id]) != int(_required[id]):
			return false
	return true
