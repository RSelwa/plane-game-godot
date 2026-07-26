extends Node

## Autoloaded singleton "Game": handles scene transitions and carries the last round's
## result between the cockpit and the recap scene (which is a fresh scene, so the result
## must be snapshotted here before we leave the cockpit).

const MAIN_MENU := "res://scenes/main_menu.tscn"
const COCKPIT := "res://scenes/cockpit.tscn"
const SETTINGS := "res://scenes/settings.tscn"
const ROUND_RECAP := "res://scenes/round_recap.tscn"

## Snapshot of the finished round, read by round_recap. Shape:
## { success: bool, reason: String, time_left: float, rows: Array[{id,you,need,ok}] }
var last_result: Dictionary = {}

func goto(path: String) -> void:
	get_tree().change_scene_to_file(path)
