extends Control

## Settings placeholder. Real options (volume, mutators) come later.

func _ready() -> void:
	$Center/VBox/Back.pressed.connect(func() -> void: Game.goto(Game.MAIN_MENU))
