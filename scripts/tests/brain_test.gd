extends SceneTree

## Deterministic gate test for the game's logic. No editor, no rendering.
## Run headless:
##   <godot-binary> --headless --path . --script res://scripts/tests/brain_test.gd
## Exits 0 on PASS, 1 on FAIL, so it can gate a commit hook.
##
## Trois couches. CockpitBrain.self_test() couvre la logique de round (validation, dérivation par
## liste de décision, table d'opérateurs, deux exemplaires d'un même type). Les validateurs de DATA
## couvrent le contenu — dont les gardes qui maintiennent chaque constante déclarée à UN SEUL
## endroit. Enfin _test_instances() couvre le découpage instance/type au niveau DATA : c'est le
## chemin que le round emprunte réellement (place -> spawn -> roll_edgework -> build_manual_data).

func _initialize() -> void:
	var ok := true

	var brain_result := CockpitBrain.self_test()
	print(brain_result)
	ok = ok and brain_result.begins_with("SELFTEST PASS")

	var wheels_result := ModuleAirportCode.self_test()
	print(wheels_result)
	ok = ok and wheels_result.begins_with("SELFTEST PASS")

	var inst_result := _test_instances()
	print(inst_result)
	ok = ok and inst_result.begins_with("SELFTEST PASS")

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

## Deux exemplaires du MÊME type traversant la couche data. Le bug que ça attrape : tant que tout
## était clé par id de TYPE, le second exemplaire écrasait le premier — un tableau de bord à un
## seul module là où le round en avait demandé deux, sans le moindre message.
func _test_instances() -> String:
	var log: Array = []
	var t := ModuleAirportCode.ID
	var pair: Array[ModuleInstance] = [
		ModuleInstance.new(t + "_1", t),
		ModuleInstance.new(t + "_2", t),
	]

	## PLACEMENT : deux exemplaires, deux slots distincts, et le reste en plaques vides.
	var layout := DashboardLayout.place(pair, 4821)
	var placements: Dictionary = layout["placements"]
	var placed_both: bool = placements.size() == 2 \
		and placements.has(t + "_1") and placements.has(t + "_2")
	var distinct_slots: bool = placed_both \
		and placements[t + "_1"]["slot_id"] != placements[t + "_2"]["slot_id"]
	var blanks_ok: bool = (layout["empty"] as Array).size() == DashboardLayout.slot_count() - 2 \
		and (layout["unplaced"] as Array).is_empty()
	log.append("place: both=%s distinct=%s blanks=%s" % [placed_both, distinct_slots, blanks_ok])

	## La seed doit reproduire le tableau de bord à l'identique, exemplaires compris.
	var again := DashboardLayout.place(pair, 4821)
	var deterministic: bool = again["placements"] == placements
	log.append("place deterministic=%s" % deterministic)

	## EDGEWORK : même type, même stratégie, mais le flux rng avance — donc deux plateaux
	## différents. C'est ce qui fait que deux exemplaires ne sont pas la même énigme (Modèle B).
	var rng := RandomNumberGenerator.new()
	rng.seed = 4821
	var board_a := ModuleRegistry.roll_edgework(t, rng)
	var board_b := ModuleRegistry.roll_edgework(t, rng)
	var boards_differ: bool = not board_a.is_empty() and not board_b.is_empty() and board_a != board_b
	log.append("edgework differs per instance=%s" % boards_differ)

	## CHARGE DE DÉRIVATION : les facts sont dédupliqués par type (une plaque reste une plaque),
	## et un module à molettes n'entre pas dans "modules" (il n'a pas de liste de décision).
	var payload := ModuleRegistry.build_manual_data(pair)
	var single := ModuleRegistry.build_manual_data([pair[0]] as Array)
	var facts_deduped: bool = (payload["facts"] as Array).size() == (single["facts"] as Array).size()
	var wheels_excluded: bool = (payload["modules"] as Dictionary).is_empty()
	log.append("payload: facts_deduped=%s wheels_excluded=%s" % [facts_deduped, wheels_excluded])

	var all_ok := placed_both and distinct_slots and blanks_ok and deterministic \
		and boards_differ and facts_deduped and wheels_excluded
	return ("SELFTEST PASS :: instances :: " if all_ok else "SELFTEST FAIL :: instances :: ") \
		+ " | ".join(log)
