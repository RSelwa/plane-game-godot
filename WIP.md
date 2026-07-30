# Chantier en cours

État du travail non terminé. Les **décisions** vivent dans `CLAUDE.md` ; ce fichier ne garde que
« où on s'est arrêté ». À vider quand le chantier est fini.

Dernière mise à jour : session du 30/07/2026.

---

## Chantier : seam entrées (clavier/souris/manette) + résolution — FAIT

But : que brancher une manette plus tard soit **un bind dans `project.godot`, pas une réécriture**.
Toutes les entrées passent maintenant par des **actions InputMap**, plus une seule touche en dur.

- **`project.godot [input]`** : 9 actions. `interact` (clic gauche / A), `camera_look` (clic droit),
  `focus_next` (Tab / RB), `focus_prev` (LB), `back` (Échap / B), `cam_look_left/right/up/down`
  (stick droit, axes 2/3). Éditables dans l'UI Input Map de l'éditeur.
- **`camera_rig.gd`** : `_unhandled_input` ne lit plus `KEY_TAB`/`KEY_ESCAPE`/`MOUSE_BUTTON_RIGHT`
  mais `event.is_action_pressed(...)`. `_cycle_focus(dir)` prend un sens (Tab avance, LB recule).
  Nouveau `_process` : free-look au stick droit via `Input.get_vector`, mêmes clamps que la souris,
  coupé quand on est focus. Nouvel export `stick_sensitivity` (deg/s).
- **Verrou d'interaction sur le focus** : un control ne répond au clic **que si la caméra est
  zoomée sur son module**. En overview un clic ne fait que **choisir** un module à zoomer. Drapeau
  `_interactable` sur `cockpit_control.gd` + `airport_code_view.gd` (`set_interactable`), piloté par
  `flight.gd._on_focus_changed` branché sur `camera_rig.focus_changed`. Au démarrage tout est inerte
  (`_on_focus_changed(null)`). **Nouveau flux de jeu : clic droit sur un module → zoom → clic gauche
  sur ses boutons.**
- **Résolution adaptative** : `window/stretch/mode` passé de `canvas_items` (rendu 2D fixe, la 3D
  était étirée → « même résolution » en redimensionnant) à **`disabled`** (la 3D rend à la
  résolution native de la fenêtre, la caméra ajuste son aspect). Taille de base 1280×720. Le HUD est
  déjà ancré (CanvasLayer `UI` + `Center` du menu), donc rien à réancrer.

**Différé (features, pas des seams — l'archi les supporte déjà, zéro dette) :**
- Nav **directionnelle** manette (D-pad gauche/droite/haut/bas entre modules). Les slots ont
  `<zone>_r<row>_c<col>`, donc les voisins spatiaux sont calculables. Aujourd'hui : cycle next/prev.
- **A qui valide un bouton précis** quand on est zoomé : demande un curseur/sélecteur par module
  (une molette parmi trois). `interact` est défini et prêt, mais camera_rig ne le consomme pas.
- **Tuning stick** (deadzone fine, courbe) + écran de rebind : prématuré tant que la boucle n'est
  pas prouvée fun.

**Non testé par Claude** (GDScript runtime = playtest, cf. méthode de travail) : brancher une
manette, vérifier le stick, le cycle bumpers, le verrou focus, et le redimensionnement de fenêtre.

---

**Session précédente (29/07) :** le module `airport_code` **fonctionne de bout en bout**. Plateau tiré de la
seed → 3 molettes cliquables → Submit jugé par le brain → lampe éteinte / rouge / verte →
verrou. Le projet est redevenu runnable. Le chantier « module AIRPORT CODE » est donc
essentiellement **fini** ; ce qui reste est du contenu et le manuel de la tour.

---

## Chantier : module AIRPORT CODE — FAIT

Le pilote lit 18 lettres à la tour. La tour cherche le **seul** code aéroport que ces molettes
peuvent épeler, et le fait composer. La réponse est **dérivée** des molettes générées.

### Le pipeline complet, tel qu'il tourne aujourd'hui

```
Mission (data/mission.gd, typée)
  → ModuleSpawner.spawn()                     instancie le prefab dans le slot
  → ModuleRegistry.roll_edgework(id, rng)     → ModuleAirportCode.generate(pool, rng)
  → brain.set_module_edgework()               le plateau + la réponse, côté autorité
  → brain.register_control("<id>/w0..w2")     1 module = 3 controls, états = les lettres
  → vue.bind_wheels(module_id, ids, wheels)   la vue ne reçoit QUE les lettres
  → brain.generate_flight(seed)               (efface le required — d'où l'ordre)
  → flight._apply_module_answers()            set_required × 3 depuis target_index
```

### Fait cette session

- **`Mission` est un type** (`data/mission.gd`, `class_name Mission extends RefCounted`,
  `_init` exige `id`/`modules`/`time`/`lives`). `flight.gd` et `data/modes.gd` retypés ; tous
  les `.get("clé", défaut)` supprimés. `MissionParams` a été envisagé puis abandonné (GDScript
  n'a pas d'arguments nommés, donc l'objet n'achetait que du type, pas de lisibilité à l'appel).
- **`_resolve_mission()`** (`flight.gd:74`) retourne une mission **provisoire** codée en dur —
  à remplacer par `data/mission_gen.gd`.
- **`ModuleRegistry`** : `airport_code` enregistré dans `defs()` ; `KIND_STATES`/`KIND_WHEELS`
  avec **deux validateurs** (`_validate_states_module` / `_validate_wheels_module`) ;
  `GEN_AIRPORT_WHEELS` + `roll_edgework()` (le point de rencontre pool ↔ algorithme) ;
  `wheel_control_id()` (seul endroit où `<module>/w<i>` s'écrit) ; `_validate_prefab()` accepte
  une racine `Node3D` pour un module à molettes ; `build_manual_data()` **exclut** les modules à
  molettes (ils n'ont pas de liste de décision — voir `CLAUDE.md`, « The manual is a BOOK »).
- **`ControlStore.request_cycle(id, step := 1)`** — le bouton `−` existe. Double modulo, parce
  qu'en GDScript `-1 % 6 == -1`.
- **`ModuleStore`** : le record gagne `edgework` + `control_ids`, avec copies profondes en
  sortie (l'edgework contient la réponse). `CockpitBrain` délègue les 4 accesseurs et gagne
  `module_matches_required()` — *« est-il correct MAINTENANT »*, à ne pas confondre avec
  `module_correct()`, *« a-t-il été marqué correct »*.
- **`generate_flight()` n'appelle plus `_modules.clear()`** : le jeu de modules est établi par le
  spawn, qui a lieu avant. Même famille de piège que `clear_required()`.
- **`flight.gd`** : `_modules` / `_control_owner` / `_control_module` remplacent `_controls` ;
  `_build_dashboard()` aiguille sur `kind` ; `_register_wheels_module()` fait le « 1 module =
  N controls » ; `_apply_module_answers()` pose les réponses **après** `generate_flight` ;
  `_on_submit_requested()` ; `_on_module_status_changed()` ; le **verrou** dans
  `_on_cycle_requested()`. `_brain` est typé `CockpitBrain` (plus de `Variant`).
- **`cockpit_control.gd`** : `cycle_requested(id, step)` — une seule forme de signal pour tous
  les controls, émise avec `1`.
- **`airport_code_view.gd`** : les 3 `Label3D` lisent leur lettre, les 6 boutons `±` passent par
  un seul handler (`_on_button_input.bind(wheel, step)`), `Submit`, et la lampe
  (`apply_module_status`). La vue ne reçoit jamais `target`.
- **Orientation** : le `.glb` arrivait couché (Blender Z-up → Godot Y-up). Corrigé sur la racine
  du prefab `airport_code.tscn`.
- **`max_instances` passé à 1** : deux exemplaires = deux fois la même conversation. La variété
  doit venir d'un autre TYPE de module.
- **Panneau debug F3** : dans `UI/Status` (`flight.gd:_debug_text()`), donc aucune modification
  de scène. Affiche seed, les 6 lettres de chaque molette, la lettre attendue, le code cible, le
  code composé, valide oui/non. Lit **uniquement** le brain, jamais la vue.

### Ce qui reste sur ce module

1. **Le pool doit passer de 6 à 25-40 codes** (`data/facts.gd:35`). Le module est correct mais
   sans tension : ~0,5 « faux espoir » à 6 codes, ~3,9 à 30. **C'est le vrai réglage de
   difficulté** (KTANE Password utilise 35 mots). Mesuré, ne pas refaire les simulations.
2. **La page du manuel** : prose générique + le pool imprimé (la table de consultation de la
   tour). Voir le chantier « livre » ci-dessous.
3. Lien statut module ↔ LAND / recap : aujourd'hui le Submit marque le module, mais `_attempt_land`
   ne regarde encore que `brain.is_valid()` sur tous les controls.

### Le générateur — conclusions déjà mesurées (ne pas refaire les simulations)

Cible `T = t₁t₂t₃`. Trois molettes de 6 lettres. Un code du pool est épelable si ses 3 lettres
sont chacune sur sa molette. **Il en faut exactement un.** Méthode : tirer, vérifier,
recommencer. Sur un pool de 30 codes réels : **1,5 tirage en moyenne**, pire cas mesuré = 1 seule
lettre à exclure obligatoirement, et ~3,9 faux espoirs gratuits par tirage (codes dont 2 lettres
sur 3 sont disponibles). Détails : deux molettes peuvent porter la même lettre ; la même lettre
deux fois sur UNE molette gaspille un emplacement ; le départ n'est jamais déjà la solution.

### Décision : la cible n'est PAS `arriving_airport`

Ce fact est affiché sur un placard (anchor `side_panel`) : le pilote lirait la solution sur le
mur. Le module a sa **propre** cible, tirée de la seed. Une mission « destination inconnue »
(placard retiré, le module répond à la question) est un chantier séparé.

---

## Chantier : le livre du manuel (décidé, rien écrit)

Décision complète dans `CLAUDE.md`, « The manual is a BOOK, not a round summary ». Résumé :
`manual_text()` doit rendre **tous** les types enregistrés, toujours, et non les modules du
round — sinon la tour voit le tableau de bord et le pilote n'a plus rien à décrire.

À faire : un rendu « une section par type » indépendant du round, avec pour `airport_code` de la
prose + **le pool imprimé**. La charge de dérivation (`build_manual_data`) reste par round, elle.

---

## Chantier : générateur de round (`data/mission_gen.gd`)

Spec dans `CLAUDE.md`, « Round = parameters + a seed ». Rien écrit.

1. `generate(seed, params) -> Mission` ; pioche des **instances** (doublons autorisés,
   `max_instances` respecté)
2. remplacer `flight.gd:74` `_resolve_mission()`, aujourd'hui codé en dur
3. ajouter le seuil d'apparition (`difficulty`) dans la fiche d'`airport_code`
4. quand les suffixes d'instance arrivent (`airport_code_1`), `ModuleRegistry.roll_edgework()`
   devra recevoir l'id de **TYPE**, pas l'id d'instance (commentaire déjà posé dans la fonction)

---

## Autres restes connus

- **`module_spawner.gd:104`** : un module multi-cellules est ancré sur le marqueur de sa
  **première** cellule, donc un `footprint [2,1]` déborde de 0,25 vers la droite. Le centrage est
  un chantier du spawner.
- **Panneau debug** : il vit dans `UI/Status`. Le sortir dans son propre panneau, toujours caché
  par défaut, quand le HUD sera repris.
- **`scripts/tests/brain_test.gd`** : `CockpitBrain.self_test()` ne couvre pas encore l'edgework,
  `module_matches_required`, ni le chemin go-around.
- Assets de test à supprimer : `res://test_sphere.tscn`, `res://sphere_mesh.tres`.

---

## Méthode de travail (à respecter à la reprise)

**Changé cette session.** Le développeur ne veut plus taper le code lui-même : il fournira des
**modèles 3D grossiers** et décrira **ce que chaque module doit faire**, et Claude code.

- Claude écrit le code (`Write`/`Edit`), le développeur fait la 3D et le playtest
- **expliquer court.** Un pavé le perd : il a des questions dès le premier tiers
- il apprend Godot/GDScript en lisant, donc dire *pourquoi* un choix, pas seulement quoi
- donner les chemins précis dans l'éditeur (FileSystem, Inspecteur, onglet Script) et les
  numéros de ligne
- l'indentation GDScript est en **tabulations** ; l'éditeur Godot ré-indente ce qu'on y colle,
  d'où des collages multipliés (1 → 3 → 5 tabs) — si ça arrive, Claude réécrit le fichier
- **le `print()` du jeu lancé n'est pas lisible par Claude** (limite MCP). Le développeur lance
  avec F5, lit le panneau **Sortie**, et rapporte
- Claude n'a pas eu les outils MCP moteur cette session (pas de screenshot) : pour tout ce qui
  est visuel, demander une **capture d'écran** plutôt que déduire des transforms
- pour rejouer un vol : nœud `Flight` de `scenes/flight.tscn` → Inspecteur → **Fixed Seed**
- **F3** en jeu affiche la réponse
