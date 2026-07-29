class_name ModuleRegistry
extends RefCounted

## THE MODULE REGISTRY — the one place that knows every module type exists.
##
## A round names module ids and nothing else; the registry resolves an id to its full
## definition. Adding a module type = add a file under data/modules/ and one line in defs().
## Nothing else in the game changes.
##
## build_manual_data() is the bridge to the brain: it turns a round's module list into
## exactly the { "facts": [...], "modules": {...} } shape CockpitBrain.load_manual_json
## already eats, with the fact set narrowed to the union of what those modules read.


## Deux FORMES de module existent, validées par des règles différentes. `kind` nomme laquelle.
##
## Un fichier de data écrit cette chaîne en littéral : il ne peut pas référencer une constante
## d'ici sans créer une référence de classe cyclique (le registry référence déjà le module).
## Donc un `kind` inconnu est ATTRAPÉ ci-dessous au lieu d'être rendu impossible — même échappa-
## toire que les littéraux de .tscn (CLAUDE.md, « ONE OWNER PER CONSTANT »).
const KIND_STATES := "states"
const KIND_WHEELS := "wheels"

## Une stratégie de génération d'edgework, NOMMÉE. Par défaut l'edgework est de la pure data
## (gen:number, pick-dans-un-pool) ; un type dont le contenu porte une VRAIE contrainte — ici
## « exactement un code épelable » — déclare une stratégie en code (CLAUDE.md, Modèle B).
## Le fichier de data écrit la chaîne en littéral, même échappatoire que `kind` ci-dessus.
const GEN_AIRPORT_WHEELS := "airport_wheels"

## Every registered module type, keyed by id.
static func defs() -> Dictionary:
	return {
		ModuleAirportCode.ID: ModuleAirportCode.def()
	}

static func ids() -> Array:
	return defs().keys()

static func has(id: String) -> bool:
	return defs().has(id)

## Full definition for a module id. Empty dictionary when the id is unknown.
static func def(id: String) -> Dictionary:
	return defs().get(id, {})

## Assemble the manual payload for one mission: the union of the facts its modules read
## (in first-seen order, deduplicated) plus each module's decision list, keyed by module id.
## Module id == control id for state_match modules, which is what the brain expects today.
static func build_manual_data(module_ids: Array) -> Dictionary:
	var facts: Array = []
	var seen: Dictionary = {}
	var modules: Dictionary = {}
	var all := defs()
	for id in module_ids:
		if not all.has(id):
			push_error("ModuleRegistry: mission names unknown module '%s'" % id)
			continue
		var d: Dictionary = all[id]
		for fact_id in d.get("facts", []):
			if seen.has(fact_id):
				continue
			seen[fact_id] = true
			var fact_def := CockpitFacts.def(fact_id)
			if fact_def.is_empty():
				push_error("ModuleRegistry: module '%s' reads unknown fact '%s'" % [id, fact_id])
				continue
			facts.append(fact_def)
		## Un module à molettes n'a pas de liste de décision, et ses controls ne portent pas
		## l'id du module (voir wheel_control_id) : le mettre dans la charge du manuel ferait
		## rejeter un « unknown control » à chaque round (manual_engine.gd:97). Sa page du
		## livre est de la prose + le pool imprimé, pas un if/else.
		## Ses FACTS, eux, restent tirés au-dessus — une plaque du cockpit reste une plaque.
		if d.get("kind", KIND_STATES) != KIND_WHEELS:
			modules[id] = d.get("rules", [])
	return { "facts": facts, "modules": modules }

## Static sanity pass over every registered module: catches a typo'd fact, an unknown
## operator, or a rule setting a state the module does not declare. Returns an empty
## array when the registry is clean. Cheap enough to run on load.
##
## Also guards the three things that CANNOT be reduced to a single declaration by the language
## and so have to be kept honest by a check instead:
##   - a prefab re-declaring control_id / state_labels (a .tscn stores literals, it cannot
##     reference a constant), which would silently shadow the data file
##   - a fact id drifting off snake_case, the convention the id strings share with control /
##     module / mission / mode ids
##   - a module's `kind`, written as a literal in its data file (see KIND_STATES above)
static func validate() -> Array:
	var errors: Array = []
	errors.append_array(_validate_fact_id_convention())
	for id in defs():
		var d: Dictionary = def(id)
		if d.get("id", "") != id:
			errors.append("module '%s': def().id is '%s'" % [id, d.get("id", "")])
		errors.append_array(_validate_prefab(id, d))
		match d.get("kind", KIND_STATES):
			KIND_STATES:
				errors.append_array(_validate_states_module(id, d))
			KIND_WHEELS:
				errors.append_array(_validate_wheels_module(id, d))
			var unknown:
				errors.append("module '%s': unknown kind '%s'" % [id, str(unknown)])
	return errors

## Un module à ÉTATS : une liste d'états fixe, plus une liste de décision qui en choisit un.
## Le moteur générique le traite de bout en bout — un module de cette forme n'a AUCUN code.
static func _validate_states_module(id: String, d: Dictionary) -> Array:
	var errors: Array = []
	var states: Array = d.get("states", [])
	if states.size() < 2:
		errors.append("module '%s': needs at least 2 states" % id)
	for fact_id in d.get("facts", []):
		if not CockpitFacts.has(fact_id):
			errors.append("module '%s': unknown fact '%s'" % [id, fact_id])
	var declared_facts: Array = d.get("facts", [])
	var rules: Array = d.get("rules", [])
	var branch := 0
	var has_else := false
	for rule in rules:
		var set_label: String = rule.get("else", rule.get("set", ""))
		if rule.has("else"):
			has_else = true
		if not states.has(set_label):
			errors.append("module '%s' branch %d: sets undeclared state '%s'" % [id, branch, set_label])
		for cond in rule.get("when", []):
			var fact_id: String = cond.get("fact", "")
			if not CockpitFacts.has(fact_id):
				errors.append("module '%s' branch %d: unknown fact '%s'" % [id, branch, fact_id])
			elif not declared_facts.has(fact_id):
				errors.append("module '%s' branch %d: reads fact '%s' missing from its 'facts' list" % [id, branch, fact_id])
			if not CockpitOps.is_known(cond.get("op", "")):
				errors.append("module '%s' branch %d: unknown op '%s'" % [id, branch, cond.get("op", "")])
		branch += 1
	if not has_else:
		errors.append("module '%s': decision list has no final 'else' default" % id)
	return errors

## Un module à MOLETTES : ni états ni règles. Son contenu est tiré par INSTANCE depuis la seed,
## et sa réponse est CHERCHÉE dans ce contenu (CLAUDE.md, Modèle B). Ses états n'existent donc
## qu'à l'exécution — les déclarer serait une deuxième source de vérité.
static func _validate_wheels_module(id: String, d: Dictionary) -> Array:
	var errors: Array = []
	if int(d.get("wheel_count", 0)) < 1:
		errors.append("module '%s': wheel_count must be at least 1" % id)
	if int(d.get("wheel_size", 0)) < 2:
		errors.append("module '%s': wheel_size must be at least 2" % id)
	if int(d.get("max_instances", 0)) < 1:
		errors.append("module '%s': max_instances must be at least 1" % id)
	if d.has("states") or d.has("rules"):
		errors.append("module '%s': a wheels module declares neither states nor rules" % id)
	if str(d.get("edgework_gen", "")).is_empty():
		errors.append("module '%s': a wheels module needs an edgework_gen strategy" % id)

	return errors

  ## Le prefab d'un module, vérifié selon sa FORME.
  ##
  ## Module à ÉTATS : la racine est un CockpitControl, et il doit laisser control_id et
  ## state_labels VIDES — ModuleSpawner les pousse depuis def() au spawn. Un prefab qui les
  ## remplit est une deuxième source de vérité que les autres contrôles d'ici ne peuvent pas
  ## voir : eux valident les règles contre def()["states"], alors que le brain enregistrerait
  ## ce que la SCÈNE portait. Les deux divergent en silence.
  ##
  ## Module à MOLETTES : la racine est un Node3D nu contenant N molettes. Une racine
  ## CockpitControl signifierait UN control — précisément la forme que ce module n'a pas.
static func _validate_prefab(id: String, d: Dictionary) -> Array:
	var errors: Array = []
	var scene_path: String = d.get("scene", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			errors.append("module '%s': missing scene '%s'" % [id, scene_path])
			return errors
	var packed: PackedScene = load(scene_path)
	if packed == null:
			errors.append("module '%s': could not load '%s'" % [id, scene_path])
			return errors
	var probe := packed.instantiate()
	if d.get("kind", KIND_STATES) == KIND_WHEELS:
			if probe is CockpitControl or not (probe is Node3D):
					errors.append("module '%s': wheels prefab root must be a plain Node3D, got %s" % [id, probe.get_class()])
	elif probe is CockpitControl:
			var control := probe as CockpitControl
			if not control.control_id.is_empty():
					errors.append("module '%s': prefab hardcodes control_id '%s' — remove it, the spawner pushes it" % [id, control.control_id])
			if control.state_labels.size() > 0:
					errors.append("module '%s': prefab hardcodes state_labels %s — remove it, the spawner pushes def().states" % [id, str(control.state_labels)])
	else:
			errors.append("module '%s': prefab root is not a CockpitControl" % id)
	probe.free()
	return errors

## Fact id STRINGS share one convention with control / module / mission / mode ids:
## lowercase snake_case. The constant naming them stays SCREAMING_CASE.
static func _validate_fact_id_convention() -> Array:
	var errors: Array = []
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_"
	for fact_id in CockpitFacts.ids():
		var s := str(fact_id)
		for i in s.length():
			if allowed.find(s[i]) < 0:
				errors.append("fact '%s': id must be lowercase snake_case" % s)
				break
	return errors

## Un module à molettes enregistre UN control par molette. Seul endroit où cet id s'écrit —
## la vue, le brain et le panneau debug passent tous par ici.
static func wheel_control_id(module_id: String, wheel: int) -> String:
	return "%s/w%d" % [module_id, wheel]

## Roule l'edgework d'UNE instance. C'est le point de rencontre entre le CONTENU (le pool
## d'aéroports, qui vit dans data/facts.gd) et l'ALGORITHME (qui vit dans le module) : le
## module ignore les facts, le registry ignore l'algorithme. Dictionnaire vide = ce module
## n'a pas d'edgework.
##
## `module_id` est aujourd'hui aussi l'id de TYPE. Quand mission_gen introduira les suffixes
## d'instance (airport_code_1), c'est le type qu'il faudra passer ici.
static func roll_edgework(module_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var d := def(module_id)
	match str(d.get("edgework_gen", "")):
		"":
			return {}
		GEN_AIRPORT_WHEELS:
			return ModuleAirportCode.generate(CockpitFacts.airport_codes(), rng)
		var unknown:
			push_error("ModuleRegistry: module '%s' names unknown edgework_gen '%s'" % [module_id, str(unknown)])
			return {}
