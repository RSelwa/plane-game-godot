extends SceneTree

## Deterministic gate test for the CockpitBrain logic. No editor, no rendering.
## Run headless:
##   <godot-binary> --headless --script res://scripts/tests/brain_test.gd
## Exits 0 on PASS, 1 on FAIL, so it can gate a commit hook.

func _initialize() -> void:
	var result := CockpitBrain.self_test()
	print(result)
	quit(0 if result.begins_with("SELFTEST PASS") else 1)
