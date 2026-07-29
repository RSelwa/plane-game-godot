extends SceneTree

## Deterministic gate test for the game's logic. No editor, no rendering.
## Run headless:
##   <godot-binary> --headless --path . --script res://scripts/tests/brain_test.gd
## Exits 0 on PASS, 1 on FAIL, so it can gate a commit hook.
##
## Two halves. CockpitBrain.self_test() covers the round logic (validation, the decision-list
## derive, the operator table). The DATA validators cover the content — including the guards
## that keep every constant declared in exactly ONE place: a prefab must not re-declare what
## its data file owns, and fact ids must stay snake_case.

func _initialize() -> void:
	var ok := true

	var brain_result := CockpitBrain.self_test()
	print(brain_result)
	ok = ok and brain_result.begins_with("SELFTEST PASS")

	var wheels_result := ModuleAirportCode.self_test()
	print(wheels_result)
	ok = ok and wheels_result.begins_with("SELFTEST PASS")

	for pair in [
		["ModuleRegistry", ModuleRegistry.validate()],
		["DashboardLayout", DashboardLayout.validate()],
	]:
		var label: String = pair[0]
		var errors: Array = pair[1]
		if errors.is_empty():
			print("DATA PASS :: %s clean" % label)
		else:
			ok = false
			print("DATA FAIL :: %s :: %s" % [label, " | ".join(errors)])

	quit(0 if ok else 1)
