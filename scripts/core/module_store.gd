extends RefCounted
class_name ModuleStore

## The modules of the CURRENT flight, as one RECORD per module-INSTANCE, keyed by id. General
## to every module type. Authoritative (server-side in multiplayer — the view only renders it).
##
## A record grows over the build: today { id, type, status }; the wiring slice adds
## control_ids and slot. Keeping it a MAP keyed by id (not an Array) means O(1) lookup by id
## (module_status("ac_1")); _order preserves the flight's module order for iteration — the same
## dict+order pattern ControlStore uses.
##
## status: null = untried, WRONG, or CORRECT. It drives the module's cockpit light. A fresh
## flight clears the store, so every module starts unregistered/untried.

const WRONG := "false"
const CORRECT := "correct"

var _records: Dictionary = {}   # id -> { id, type, status }
var _order: Array = []

func clear() -> void:
	_records.clear()
	_order.clear()

## Register one module instance for this flight. status starts untried (null).
func register(id: String, type: String) -> void:
	if id.is_empty():
		push_error("ModuleStore: empty module id ignored.")
		return
	if _records.has(id):
		push_error("ModuleStore: duplicate module id '%s' ignored." % id)
		return
	_records[id] = {"id": id, "type": type, "status": null}
	_order.append(id)

func has(id: String) -> bool:
	return _records.has(id)

## Module ids in flight order.
func ids() -> Array:
	return _order.duplicate()

func module_type(id: String) -> String:
	return str(_records[id]["type"]) if _records.has(id) else ""

## A copy of the whole record (safe to read, cannot mutate the store). Empty when unknown.
func record(id: String) -> Dictionary:
	return (_records[id] as Dictionary).duplicate() if _records.has(id) else {}

## Current status, or null when untried (or the module is not registered).
func status(id: String):
	return _records[id]["status"] if _records.has(id) else null

func set_status(id: String, value: String) -> void:
	if not _records.has(id):
		push_error("ModuleStore: status for unknown module '%s'." % id)
		return
	_records[id]["status"] = value

## Back to untried (keeps the record, only clears its status).
func reset(id: String) -> void:
	if _records.has(id):
		_records[id]["status"] = null

func is_correct(id: String) -> bool:
	return _records.has(id) and _records[id]["status"] == CORRECT
