# Module : Saisie aéroport (3 lettres) — contrat à coder

But : le joueur compose un code aéroport 3 lettres (ex. BCN) avec 6 boutons (up/down par cellule) + un bouton submit. Lore : la destination.

C'est le premier module `value_match`. On le code à la main pour apprendre. Ce fichier = le contrat convenu, pour ne pas dériver.

## Décisions d'architecture (ne pas casser)

- **Le brain a l'autorité, la scène est bête.** La valeur actuelle vit dans le brain, pas dans le module. La scène affiche + collecte l'input, elle ne calcule jamais le correct/faux.
- **Store indexé par id.** Pas de variable par contrôle : tout passe par les dictionnaires du brain (`_state`, `_required`) indexés par un id string, et les méthodes génériques qui existent déjà (`register_control`, `request_cycle`, `get_state`, `is_valid`...). Ajouter ce module n'ajoute PAS de méthode par cellule.
- **Analogie websocket.** Module = client qui émet une intention (`cycle_requested(id)`). Brain = serveur : il valide l'id, change l'état, ré-émet `state_changed(id, n)`, la scène se redessine. Le serveur ne fait jamais confiance au client → validation au bord (déjà dans `request_cycle` / `register_control`).

## Les 3 cellules = 3 sous-contrôles

Chaque cellule est un contrôle normal à 26 états (A..Z = 26 labels). Up/down sur une cellule = `request_cycle` sur son id. Aucun nouveau code brain.

**Ids uniques** (sinon collision → on ferait tourner le mauvais contrôle). Préfixer avec l'id de slot du dashboard, ex :
```
"<slot_id>/airport_c0"
"<slot_id>/airport_c1"
"<slot_id>/airport_c2"
```

## Le check : `value_match` (la seule chose neuve, générique, réutilisée)

- Le correct dérive du seed : `correct == arriving_airport` (fait). Éventuellement une transformation (reverse, décalage) plus tard pour éviter la simple recopie.
- L'actual = les 3 lettres composées, lues depuis l'état des 3 cellules du brain.
- Comparaison string : `actual == correct`, faite **dans le brain**.
- Cette stratégie servira aussi radio / coordonnées / clavier. On l'écrit une fois.

## Validation par module (style KTANE, pas le LAND global)

- On oublie le LAND global pour l'instant. Chaque module se valide seul.
- **Submit** → déclenche une vérif de CE module dans le brain (ex. `validate_module(id)` qui compare actual vs correct pour ce module).
- Le brain renvoie ok/pas ok → la scène allume la diode (vert = résolu). Faux = strike (une vie en moins), à la KTANE.
- La diode et le strike sont des réactions de la vue au résultat renvoyé par le brain. La décision reste dans le brain.

## Qui possède quoi

```
BRAIN (données + décisions)
  _state[id], _required[id]                     <- les 3 cellules + leur correct
  register_control / request_cycle / get_state / is_valid   <- génériques, existent
  value_match (nouveau, générique)              <- compare la string dérivée vs actual
  validate_module(id) (nouveau)                 <- vérif d'un seul module au submit

SCÈNE / module (visuel + input)
  6 boutons up/down -> émettent cycle_requested(cell_id)   (intention)
  reçoit state_changed -> affiche la lettre (0..25 -> A..Z)
  bouton submit -> demande au brain de valider ce module
  diode -> réagit au résultat renvoyé
  aucune valeur canonique, aucun calcul de correct
```

## À décider en codant (petits points ouverts)

- La string actuelle : recomposée par le brain à partir des 3 cellules, ou stockée à part ? (le plus propre : recomposée depuis les 3 sous-états, pas de doublon de stockage.)
- Transformation ou recopie directe de `arriving_airport` ? (démarrer en recopie directe pour faire marcher le flux, ajouter une transfo après.)
- Forme data du module dans `data/modules/` : déclarer les 3 sous-contrôles + `check: "value_match"` + la cible (`@arriving_airport`).

## État du projet quand on a écrit ça

- Migration terminée : logique de jeu 100% GDScript (`scripts/core/cockpit_brain.gd`), l'ancien `CockpitBrain.cs` supprimé. Self-test OK.
- L'addon MCP reste en C# (gardé pour plus tard, pas utilisé sur le Mac).
- Voir `structure.md` pour le fonctionnement du brain.
