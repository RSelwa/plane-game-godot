extends Control

## Round debrief. Reads Game.last_result (snapshotted by the cockpit before the scene
## change) and shows success/failure plus a per-control "you set X / needed Y" table so
## players learn what went wrong. Retry rolls a fresh round; Menu returns to the title.

func _ready() -> void:
	var r: Dictionary = Game.last_result
	var ok: bool = r.get("success", false)

	var header: Label = $Center/VBox/Header
	header.text = "LANDED SAFELY" if ok else "CRASH"
	header.modulate = Color(0.3, 1.0, 0.45) if ok else Color(1.0, 0.35, 0.35)

	var reason: String = r.get("reason", "")
	if ok:
		$Center/VBox/Sub.text = "Welcome to your destination."
	else:
		$Center/VBox/Sub.text = "The investigation board thanks your crew.\n" + reason

	var lines: Array[String] = []
	for row in r.get("rows", []):
		var mark := "[ OK ]" if row.get("ok", false) else "[FAIL]"
		lines.append("%s  %s   you: %s   /   need: %s" % [mark, row["id"], row["you"], row["need"]])
	$Center/VBox/Debrief.text = "\n".join(lines)

	$Center/VBox/Buttons/Retry.pressed.connect(func() -> void: Game.goto(Game.COCKPIT))
	$Center/VBox/Buttons/Menu.pressed.connect(func() -> void: Game.goto(Game.MAIN_MENU))
