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
	_records[id] = {"id": id, "type": type, "status": null, "edgework": {}, "control_ids": []}
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
	
## L'EDGEWORK par instance : le contenu local que cette instance a tiré de la seed (les molettes
## et leurs lettres). C'est lui qui fait que deux instances du MÊME type sur un tableau de bord
## tombent sur des réponses différentes alors que les facts du vol sont identiques (Modèle B).
func set_edgework(id: String, edgework: Dictionary) -> void:
	if not _records.has(id):
		push_error("ModuleStore: edgework for unknown module '%s'." % id)
		return
	_records[id]["edgework"] = edgework.duplicate(true)

  ## Copie PROFONDE : l'edgework contient la réponse du round (target_index). Rendre la référence
  ## vivante laisserait une vue la modifier — et en multijoueur, un client la trafiquer.
func edgework(id: String) -> Dictionary:
	return (_records[id]["edgework"] as Dictionary).duplicate(true) if _records.has(id) else {}

  ## Les controls que ce module a enregistrés — un par molette. Remplis au câblage du round.
  ## C'est ce qui permet au recap de dire « AIRPORT CODE : faux » au lieu de lister 3 molettes.
func set_control_ids(id: String, control_ids: Array) -> void:
	if not _records.has(id):
		push_error("ModuleStore: control ids for unknown module '%s'." % id)
		return
	_records[id]["control_ids"] = control_ids.duplicate()

func control_ids(id: String) -> Array:
	return (_records[id]["control_ids"] as Array).duplicate() if _records.has(id) else []
