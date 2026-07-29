# Chantier en cours

État du travail non terminé. Les **décisions** vivent dans `CLAUDE.md` ; ce fichier ne garde que
« où on s'est arrêté ». À vider quand le chantier est fini.

Dernière mise à jour : session du 29/07/2026.

**Cette session :** switch/dial/lever et `data/campaign.gd` **supprimés** ; registry vide ; projet
non-runnable jusqu'à ce qu'`airport_code` soit enregistré. Le modèle de pick est décidé : **Modèle B**
(edgework par instance, manuel générique fixe par type, ids d'instance — spec dans `CLAUDE.md`,
« Module instances & per-instance edgework »). Pour `airport_code` : 3 molettes **fixes** (codes
IATA à 3 lettres) ; l'edgework tiré par instance = **les 6 lettres de chaque molette**. Le manuel
est générique et fixe (le pilote lit ses 18 lettres, la tour cherche l'unique code épelable).
(Le « 3–6 boutons » discuté était un AUTRE type hypothétique, pas ce module.)

---

## Chantier : module AIRPORT CODE (molettes de lettres, type Password de KTANE)

Le pilote lit 18 lettres à la tour. La tour cherche le **seul** code aéroport que ces molettes
peuvent épeler, et le fait composer. La réponse n'est pas un fact : elle est **dérivée** des
molettes générées.

C'est le premier module dont le **contenu interne est généré** et dont la **réponse sort de ce
contenu** (les autres lisent un fact et appliquent une règle).

### Fait

- `models/modules/password.glb` — modèle 3D
- `scenes/modules/airport_code.tscn` — 3 molettes (`Digit1/2/3` × `Minus`/`Plus`), un `Submit`,
  3 `Label3D` d'affichage (texte `"A"` en dur pour l'instant), une lumière, une caméra
- `scenes/modules/airport_code_view.gd` — la VUE (stub vide pour l'instant ; câblera labels + boutons ±)
- `data/facts.gd` — `AIRPORTS` est devenu une liste d'objets `{code, name}` + `AIRPORT_KEY`,
  `airport_codes()` (ce que consommera le générateur), `airport_name(code)` (pour l'affichage)
- `scripts/flight.gd:212` — la seed s'affiche dans le Label `UI/Status`

### Fait cette session

- `data/modules/airport_code_logic.gd` (classe `ModuleAirportCode`) — la **fiche** `def()` (Modèle B : `kind "wheels"`, `check
  "state_match"`, `wheel_count 3`, `wheel_size 6`, `max_instances 2`) **+ le générateur**
  `generate(codes, rng) -> {target, wheels:[[6]×3], target_index, start}` **+ `self_test()`**.
  Gate ajouté dans `scripts/tests/brain_test.gd`. Algorithme validé hors-moteur : 5000 seeds
  passent (unicité, `target_index` correct, pas de doublon, départ ≠ solution, déterminisme),
  1.05 tirage moyen. Le `check` retenu est `state_match` par molette (pas `value_match`) : la
  réponse d'une molette = l'index de sa lettre cible, donc le moteur générique valide sans cas
  spécial. La seule nouveauté vit dans `generate()`.
- **Caveat contenu** : pool à 6 codes → peu de tension (~0.5 « faux espoir »). Le porter à 25–40
  (voir plus bas) avant de juger le fun.
- **Store de modules** (général, tous types) : `scripts/core/module_store.gd` (`ModuleStore`).
  Une MAP keyée par id, un **record par module** `{id, type, status}` (+ `_order`). API brain :
  `register_module(id, type)` / `module_type` / `module_ids` / `module_status` / `mark_module` /
  `reset_module` / `module_correct` + signal `module_status_changed`. `status` : `null` (pas
  essayé) / `"false"` / `"correct"`. Store vidé à chaque `generate_flight`. Testé dans
  `CockpitBrain.self_test()`. **À compléter au câblage** : le record gagnera `control_ids` + `slot`
  (remplis par le spawner), un getter d'assemblage `module_view(id)` (join ModuleStore+ControlStore
  pour la lecture/recap), l'appel à `register_module` par le spawner, `mark_module` au Submit, et la
  **lumière** abonnée à `module_status_changed`.

### Pas fait

1. `ControlStore.request_cycle(id, step)` — le bouton `−` n'existe pas, seul `+1` est possible.
2. `ModuleRegistry` : brancher `kind "wheels"` — ajouter `airport_code` à `defs()` et faire
   `validate()` valider un module généré (champs `wheel_*` + scène `Node3D`) au lieu d'exiger
   états/règles/racine `CockpitControl`.
3. **1 module = N controls** : le spawner instancie 1 prefab mais enregistre 3 molettes-controls
   (`airport_code_1/w0..w2`) ; ids d'instance suffixés (débloque `control_store.gd:18`).
4. Câblage dans `flight.gd` : `generate` avec `_seed`, `register_control` × 3, `set_required` × 3.
5. La scène : les 3 `Label3D` doivent lire la lettre courante au lieu du `"A"` en dur ;
   les 6 boutons `±` doivent appeler `request_cycle`.
6. Panneau debug F3 (voir plus bas).

### Le générateur — conclusions déjà mesurées (ne pas refaire les simulations)

Cible `T = t₁t₂t₃`. Trois molettes de 6 lettres, `tᵢ` sur la molette `i`. Un code du pool est
épelable si ses 3 lettres sont chacune sur sa molette. **Il en faut exactement un.**

Méthode retenue : **tirer, vérifier, recommencer.** Remplir chaque molette avec la lettre de la
cible + 5 lettres au hasard, compter les codes épelables dans le pool, rejeter si ≠ 1.

Mesuré sur un pool de 30 codes réels :

- **1,5 tirage en moyenne** avant unicité → le rejet coûte zéro
- l'essentiel des rejets vient des codes **très différents** de la cible : chacun n'a qu'1 chance
  sur 125 de passer, mais il y en a ~27 (cible `OLY`, et `BCN` devient épelable par accident)
- les paires du type `OLY`/`ORY` (2 lettres identiques **aux mêmes positions**) sont rares (3 paires
  sur 30 codes) mais imposent une exclusion précise : `R` interdit sur la molette 2
- pire cas mesuré : **1 seule lettre à exclure obligatoirement** → 25 lettres restantes pour 5
  emplacements, aucune cible impossible
- effet de bord gratuit : ~3,9 « faux espoirs » par tirage (codes dont 2 lettres sur 3 sont
  disponibles). C'est ça qui fait travailler la tour. **C'est le vrai réglage de difficulté**,
  l'unicité n'est que la correction.

Conséquence de contenu : **le pool doit passer de 6 à 25–40 codes**, sinon le module est correct
mais sans tension (0,5 faux espoir avec 6 codes). KTANE Password utilise 35 mots.

Détails : deux molettes **peuvent** porter la même lettre (aucun effet) ; la même lettre deux fois
sur **une** molette gaspille un emplacement. Rotation de départ aléatoire, et vérifier que la
combinaison affichée au départ n'est pas déjà la solution.

### Décision prise : la cible n'est PAS `arriving_airport`

Ce fact est affiché sur un placard (`data/facts.gd`, anchor `side_panel`) : le pilote lirait la
solution sur le mur. Le module a donc sa **propre** cible, tirée de la seed. Une mission
« destination inconnue » (placard retiré, le module répond à la question) est un chantier séparé.

### Blocages connus

- **`flight.gd:91`** — `var control: CockpitControl = _controls[module_id]` exige que la racine du
  prefab soit un `CockpitControl`. Celle de `airport_code.tscn` est un `Node3D`. Et plus
  profondément : 1 `CockpitControl` = 1 control, or ce module en contient **3** (les molettes).
  Le contrat spawner→brain doit gérer « 1 module = N controls ». **Tant que l'id n'est pas dans
  `ModuleRegistry.defs()`, rien ne casse** — c'est pour ça que la fiche vient avant le câblage.
- **`cockpit_brain.gd:103`** — `generate_flight()` appelle `clear_required()`. Poser les lettres
  cibles **avant** cet appel les efface. Les poser après.
- **`module_registry.gd` `validate()`** rejettera ce module sur 3 points (racine pas
  `CockpitControl`, `states` ≥ 2 exigés, liste de décision devant finir par un `else`). Normal :
  ce module n'a ni états ni règles. À traiter avec le contrat ci-dessus.
- **`control_store.gd:18`** refuse un id de control en double → deux modules du même type sont
  impossibles aujourd'hui. Bloque le paramètre « nombre de modules » (voir `CLAUDE.md`).

---

## Chantier : générateur de round (`data/mission_gen.gd`)

Décidé cette session, **rien écrit**. La spec complète est dans `CLAUDE.md`, section
« Round = parameters + a seed ». Résumé de ce qu'il reste à faire :

1. écrire `data/mission_gen.gd` : `generate(seed, params) -> {time, lives, modules[]}` ; pioche des
   **instances** (doublons autorisés, `max_instances` respecté) — pas un type par slot
2. ajouter le seuil d'apparition (`difficulty`) + `max_instances` dans la fiche d'`airport_code`
   (seul type prévu ; les 3 placeholders sont supprimés)

FAIT cette session : `data/campaign.gd` supprimé, et `flight.gd` ne référence plus
`mission_index` / `mission_id` (`_resolve_mission()` retourne `{}` en attendant le générateur ;
`CockpitCampaign.validate()` retiré de `_report_data_errors`).

---

## Panneau debug

Pas encore construit. Ce qui existe déjà et sert de panneau debug : le Label `UI/Status` dans
`scenes/flight.tscn`, rempli par `scripts/flight.gd:202` `_refresh_status()` — il liste la seed,
les facts et l'état de chaque control.

Prévu : un panneau séparé, **caché par défaut**, basculé par F3. Contenu : seed, params, molettes
(les 6 lettres de chacune), lettre attendue, code cible, code composé, valide oui/non.

Caché par défaut parce que c'est le seul endroit du jeu qui **montre la solution**.

Il ne doit lire les réponses que **depuis le brain**, jamais depuis le spawner : au multijoueur le
brain sera côté serveur et le spawner côté client, et une réponse passée par le client est
trichable.

---

## Méthode de travail (à respecter à la reprise)

Le développeur **apprend Godot et GDScript** sur ce projet. Il veut **taper le code lui-même** et
être guidé pas à pas.

- une seule étape à la fois, et attendre son retour avant la suivante
- **explications courtes.** Un pavé le perd : il a des questions dès le premier tiers
- donner les chemins précis dans l'éditeur (panneau FileSystem, Inspecteur, onglet Script) et les
  numéros de ligne, pas juste des noms de fonctions
- l'indentation GDScript est en **tabulations** — piège récurrent
- **le `print()` du jeu lancé n'est pas lisible par Claude** (limite MCP). Le développeur lance
  avec F5 et lit le panneau **Sortie** lui-même, puis rapporte
- pour rejouer un vol : nœud `Flight` de `scenes/flight.tscn` → Inspecteur → champ **Fixed Seed**
