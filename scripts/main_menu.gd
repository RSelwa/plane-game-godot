extends Control

## Title screen. Buttons route through the Game autoload.

func _ready() -> void:
	$Center/VBox/Play.pressed.connect(func() -> void: Game.goto(Game.COCKPIT))
	$Center/VBox/Settings.pressed.connect(func() -> void: Game.goto(Game.SETTINGS))
	$Center/VBox/Quit.pressed.connect(func() -> void: get_tree().quit())
