class_name ModuleInstance
extends RefCounted

## UNE INSTANCE de module sur le tableau de bord — pas un TYPE.
##
## La distinction est tout l'objet de ce fichier. `type` nomme la FICHE (data/modules/<type>.gd,
## via ModuleRegistry.def) ; `id` nomme cet exemplaire-ci. Un round peut poser deux fois le même
## type, donc tout ce qui est PAR EXEMPLAIRE — le slot, l'edgework tiré, les controls, le statut
## de la lampe — se clé par `id`, et `type` ne sert plus qu'à retrouver la fiche.
##
## `id` doit être DÉTERMINISTE (« <type>_<n> », n = 1, 2, …), jamais tiré au hasard : la seed doit
## reproduire le vol à l'identique, et un id aléatoire ferait dériver le placement (trié par id)
## et l'ordre du flux rng.

var id: String
var type: String

func _init(p_id: String, p_type: String) -> void:
	id = p_id
	type = p_type

## Pour que le print de round (flight.gd) montre le vol au lieu d'une liste de RefCounted.
func _to_string() -> String:
	return "%s(%s)" % [id, type]
