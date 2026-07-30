extends SceneTree

## SONDE JETABLE — à supprimer. Instancie scenes/flight.tscn hors rendu et raconte l'état du
## chemin d'interaction : quelle caméra le viewport a retenue, ce qui a été spawné, quels slots
## sont focusables, et si le module devient interactif quand on force un focus.
##
## Le probe attend une FRAME : Godot diffère NOTIFICATION_READY, donc interroger juste après
## add_child() montre une scène encore vide (erreur commise au premier essai).

var _flight: Node = null
var _frames := 0

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/flight.tscn")
	_flight = packed.instantiate()
	root.add_child(_flight)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	var cam3d = root.get_camera_3d()
	var rig = _flight.get_node_or_null("Camera3D")
	print("[probe] viewport camera path = %s" % [cam3d.get_path() if cam3d != null else "<null>"])
	print("[probe] rig IS the viewport camera = %s" % [cam3d == rig])
	print("[probe] physics_object_picking = %s" % [root.physics_object_picking])

	var dash = _flight.get_node_or_null("Dashboard")
	var spawned: Dictionary = dash.controls()
	print("[probe] spawned modules = %s" % [spawned.keys()])

	var targets: Array = []
	for mid in spawned:
		var node: Node3D = spawned[mid]
		targets.append(node.get_parent())
		print("[probe]   %s parent=%s set_interactable=%s" % [
			mid, node.get_parent().name, node.has_method("set_interactable")])
		for body in node.find_children("*", "StaticBody3D", true, false):
			var shape := body.get_node_or_null("Collision") as CollisionShape3D
			var size = (shape.shape as BoxShape3D).size if shape != null and shape.shape is BoxShape3D else null
			print("[probe]     body %s pickable=%s box=%s" % [body.name, body.input_ray_pickable, size])

	## Y a-t-il un corps cliquable AILLEURS que sur les boutons ? S'il n'y en a pas, le clic droit
	## « focus le module sous le curseur » exige de viser un bouton de 4 cm : injouable.
	var all_bodies := _flight.find_children("*", "StaticBody3D", true, false)
	print("[probe] total pickable bodies in flight = %d" % all_bodies.size())

	print("[probe] focus targets = %d" % targets.size())
	if not targets.is_empty():
		rig.focus_on(targets[0])
		print("[probe] after focus_on: is_focused=%s" % rig.is_focused())
		var node: Node3D = spawned[spawned.keys()[0]]
		print("[probe] module interactable now = %s" % [node.get("_interactable")])

	quit(0)
	return true
