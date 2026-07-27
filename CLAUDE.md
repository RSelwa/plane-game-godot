# Cockpit Chaos (Working Title)

## Dev Environment (Godot-MCP)

Claude edits this Godot project live through the **Godot-MCP** integration (IvanMurzak/Godot-MCP, addon v0.20.0), in **cloud mode**. Tools are `mcp__ai-game-developer__*` (create/edit scenes, nodes, scripts, resources, screenshots).

**Architecture:** `Claude Code (.mcp.json) → https://ai-game.dev cloud (pin 16f4f388) → Godot editor plugin (outbound)`. No local MCP server process. The cloud is the server; the editor plugin dials out on startup using the machine credential at `~/.ai-game-dev/credentials.json`.

**Requirements (already satisfied):**
- **Godot 4.7.1 MONO/.NET build** — the addon is C#; the standard (GDScript-only) build cannot load it. Editor: `C:\Users\selwa\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`.
- **.NET 8 SDK** (not just runtime) — needed to build the C# addon.
- **`plane-game-godot.csproj`** at root: `Godot.NET.Sdk/4.7.1`, net8.0, packages `com.IvanMurzak.ReflectorNet 5.3.2` + `com.IvanMurzak.McpPlugin 7.5.0`, plus EmbeddedResource `addons/godot_mcp/extensions.catalog.json`. Keep these; do not delete the csproj.

**Per work session, the user does 2 things:** (1) launch the mono editor and open this project (`godot-cli open . --editor-path "<mono exe>"` or double-click); (2) approve the OAuth browser link Claude triggers once per new Claude session. Nothing else — no server terminal, no re-login.

**Gotcha:** `godot-cli status` / `wait-for-ready` probe a dev-only localhost:29110 bridge that stays off in cloud mode; they report "connection refused" even when everything works — ignore. Real readiness = `list_engine_instances` shows the instance on pin 16f4f388 and `editor-application-get-state` responds.

**Workflow:** Claude codes into the editor via MCP → user runs/tests in Godot → reports back → iterate.

---

## Vision

A cooperative game for **2 players** (with optional solo and 3-player modes) centered around **communication under pressure**.

The pilot cannot solve the situation alone. The second player has the procedures and must guide them through a failing cockpit before attempting an emergency landing.

The game is **not a flight simulator**. It is a procedural communication game.

## Gameplay Model — "Keep Talking and Nobody Explodes", in a cockpit

Direct inspiration: **Keep Talking and Nobody Explodes (KTANE)**.
- The **Pilot** = the "defuser": sits at a **procedural cockpit** (fewer buttons than a real plane), can touch everything, but has **no manual**.
- The **Tower** = the "expert": holds the manual, sees nothing, reads procedures.
- Each scenario the cockpit is **procedurally configured** (which controls exist / their required end-states vary), so the manual lookup differs every run.
- The pilot performs the correct **sequence/config of actions** the manual dictates, under a timer, then presses **LAND**. Right config → land. Wrong → crash. Same tension loop as defusing a KTANE bomb.

---

## Working method (Claude + test agent)

Build in small batches. After every **3–4 build steps (one milestone)**, spawn **two fresh-context, read-only agents**:
1. **Functional tester** — connects to the same Godot editor via MCP (screenshots, `scene-get-data`, `script-read`, run scene, `console-get-logs`, `runtime-errors-get`); reports whether the milestone actually works.
2. **Independent code reviewer** — no prior context, fresh eyes; reads the scripts and advises on architecture/quality/drift.

Both are **read-only**; only the main thread writes files, so there is never a concurrent-edit clash. The main thread incorporates the reviewer's advice before building the next milestone. **Raw models first** (CSG placeholder geometry), refine visuals later.

**MCP workflow rules (learned the hard way — follow these to stay autonomous):**
- **Resources can't be set via MCP.** ReflectorNet can't instantiate/assign resources (meshes, shapes, materials) inline via `node-modify`. Anything needing a resource (a control's `BoxShape3D` collision, a mesh, a material) must be authored in **`.tscn` text on disk**. Use CSG primitives for placeholder geometry (no resource). UI nodes (Label/Button/ColorRect) need no resources → fine to build live via MCP `node-create`/`node-modify`.
- **MCP reflection sees only C#, not GDScript.** `node-modify` and `reflection-method-call` can read/set **C# properties/methods** but are BLIND to GDScript script vars and methods. So a scene whose root has GDScript `@export` vars (e.g. `cockpit.tscn` manager NodePaths) MUST be wired in `.tscn` text, not via MCP.
- **Scripts hot-reload; scenes do NOT.** Editing a `.gd`/`.cs` file → `filesystem-reimport {files:[...]}` → the editor hot-reloads it live (no restart). Editing a `.tscn` **on disk while it's open** does NOT reload — the editor holds a cached copy. To pick up disk `.tscn` changes you must force a reload: `EditorInterface.ReloadSceneFromPath` (preferred, instant) or a full editor restart (slow).
- **C# rebuilds disconnect the cloud link.** Any `dotnet build` that changes the assembly makes the editor reload it and drop its cloud MCP connection. To restart WITHOUT forcing the user to re-authorize: use a **clean** `godot-cli close .` (polite quit — releases the cloud session) then `open` + **~75s wait** → auto-reconnects, no re-auth. **NEVER `--force` / `taskkill`** — a hard kill leaves the session dirty and forces the user to click "authorize" again. **NEVER run two editor instances** (a launch race → session churn). So: FRONT-LOAD all C#, build rarely, announce the restart; do day-to-day work in GDScript/scenes/data which never disconnect.
- **Testing:** the running game's `print()` is unreadable via MCP, and `runtime-errors-get` needs C# runtime-capture init. Test pure logic by putting it in C# and calling it via `reflection-method-call` (e.g. `CockpitBrain.SelfTest()` static). GDScript runtime behavior (clicks, round flow) = user play-test. Verify structure via `scene-get-data`, compile via `script-validate`, visuals via `screenshot-viewport` (editor viewport renders CSG; `screenshot-camera` does NOT render CSG).

---

## Project State & Technical Decisions (current)

### Architecture: C# brain (logic) + GDScript (presentation) + data (content)
Decided for testability: MCP/reflection can drive and inspect **C#** but is blind to GDScript, so the win/lose logic lives in C# where the test harness reaches it; iteration-fast presentation stays GDScript.
- **`scripts/core/CockpitBrain.cs`** — the authoritative brain (`[GlobalClass]` C# `Node`). Owns control states, required config, the FACTS (edgework), the MANUAL (decision-list engine), validation. Has a **static `SelfTest()`** the harness runs via `reflection-method-call` (returns `"SELFTEST PASS/FAIL :: …"`). Keep this the single source of truth. **A C# change forces a restart** — batch them, keep logic here complete so rebuilds stay rare.
- **`scripts/cockpit_manager.gd`** — round orchestration: registers controls into the brain, loads the manual, rolls the flight, updates UI, LAND/timer, snapshots the result → recap.
- **`scripts/cockpit_control.gd`** — control VIEW: click emits `cycle_requested`; `apply_state(state)` tilts a handle. Owns no canonical state (routes through brain — the future networking/authority seam).
- **`scripts/game.gd`** — autoload singleton `Game`: scene transitions + carries `last_result` between cockpit and recap.
- **`data/` — ALL CONTENT AS DATA.** Every file is GDScript with `static func`s, so it hot-reloads (F6, no restart, no rebuild):
  - `data/facts.gd` (`CockpitFacts`) — the fact catalog (edgework the pilot reads). Declared once, referenced by name.
  - `data/ops.gd` (`CockpitOps`) — condition operator constants, mirroring the C# `Condition.Eval` switch.
  - `data/modules/<id>.gd` (`ModuleSwitch`/`ModuleDial`/`ModuleLever`) — **one file per module TYPE**, self-contained: scene, footprint, states, the facts it reads, its decision list.
  - `data/module_registry.gd` (`ModuleRegistry`) — id → definition. `build_manual_data(ids)` assembles a mission's payload in the exact shape `LoadManualJson` eats. `validate()` catches typo'd facts/ops/states.
  - `data/dashboard.gd` (`DashboardLayout`) — the 12-slot grid (overhead 1×4 + main 2×4), the fixed fact anchors, and seeded `place(module_ids, seed)`.
  - `data/campaign.gd` (`CockpitCampaign`) — the ordered mission list. `validate()` catches unknown module ids.
  - `data/modes.gd` (`CockpitModes`) — difficulty modes as pure modifiers over a mission.
  - `data/manual.gd` (`CockpitManual`) — **LEGACY**, still what `cockpit_manager.gd` loads today. Superseded by the registry; delete once the manager reads missions.
- **Scenes:** `scenes/main_menu.tscn` (main scene) → `scenes/cockpit.tscn` → `scenes/round_recap.tscn` (+ `settings.tscn` stub).

### The puzzle engine (KTANE decision lists)
Everything generates from ONE seed (`CockpitBrain.GenerateFlight(seed)` — same seed = same flight, reproducible for tests/sharing):
- **Facts (edgework)** the pilot reads aloud: `WARN` light {GREEN,AMBER,RED}, `starting_airport`/`arriving_airport` (code pool), `flight_number` (number gen). A fact declares either `values:[…]` (pick one) or `gen:"number"` + `min`/`max`.
- **Modules = ordered decision lists** (if / else-if / else). The brain walks each list top-down; the FIRST branch whose conditions all pass sets that control's required state; a final `{else:…}` is the default.
- **Conditions are objects** `{fact, op, value?}`. Ops: `eq neq starts ends contains firstVowel lastVowel firstConsonant lastConsonant even odd`. **Y is a vowel.** Multiple conditions in one `when` = AND.
- The required config is **DERIVED, never stored or shown** — only looked up. `ManualText()` renders each module as a numbered if/else list (the tower binder).
- Authoring flow: `ModuleRegistry.build_manual_data(mission.modules)` (named constants → typo-safe) → manager `JSON.stringify`s it → `brain.LoadManualJson()` which **validates** (unknown fact/control/op/label = clear error) then derives.
- **Facts are per-module, not global.** Each module declares the facts it reads; a round rolls only the UNION of its mission's modules' facts. A two-module mission generates two facts, not the whole catalog. Unused facts are free red herrings — a red herring must be a deliberate mission choice, never catalog fallout.

### Campaign, missions, difficulty (KTANE mission model)
Difficulty is **two hand-authored knobs and nothing else**: *which* module types are on the dashboard, and *how many*. There is deliberately **no cost/budget/tier system** — a module type's complexity is inherent to the type and lives in the module's own file; the campaign only picks ids.
- **Authoring rule:** introduce exactly ONE new module type per mission, keep it beside types the crew already knows, and only raise the count once the new type is taught. Unfilled dashboard slots stay blank — an early mission is meant to *look* easy.
- **Mission** = `{id, name, time, lives, modules:[ids]}`. Ids only; adding a module type never touches `campaign.gd`, adding a mission never touches a module file.
- **Lives = LAND attempts.** `lives: 1` → a wrong configuration crashes on the first press. A failed attempt costs **a life and nothing else** — no hidden clock penalty, no mid-round surprises (the clock already supplies the tension; the time spent re-checking is the natural, visible cost). The clock hitting zero is a crash regardless of lives left.
- **LAND has three outcomes:** `LANDED` (all modules ok) / `GO_AROUND` (wrong, lives remain) / `CRASHED` (wrong on the last life, or clock zero). UI word for a spent life is **"GO-AROUND"**.
- **Modes are pure modifiers** (`lives_bonus`, `time_scale`, `feedback`), all announced before the round starts. `effective_lives` is floored at 1 — a mode may only ever be kinder than the mission.
- **Failure feedback is the real difficulty dial:** `count` ("3 systems misconfigured") is standard, `none` ("Landing aborted") is ironman. Never name the wrong module — with several attempts that collapses into brute force. Always compute the full per-module detail and gate only what the *in-round* UI shows; the post-round recap shows everything on every mode, because that is where learning happens and it costs nothing.

### Module contract
A module answers one question: **is it correct?** Two implementations, chosen by the module's `check` field — the rules stay DATA either way:
- `state_match` (default) — generic: current state == the state derived from the decision list. Simple modules (switch/dial/lever) need **zero code**; a new one is a data file plus a prefab.
- `value_match` — for modules whose answer is a computed value, not a state label (destination entry, coordinate calculation). Rules still data; `set` may be `"@fact_id"` to substitute a fact's value.
A genuinely new shape = one new named check strategy in C#, rare and batched with other rebuilds. **Never write per-module `is_correct` code** — that throws away the decision-list engine.
Check returns detail, not just a bool: `{id, ok, expected, actual}` per module, so the recap can say *"GEAR LEVER: expected DOWN, was UP"*.

### Dashboard layout & camera
**`data/dashboard.gd` (`DashboardLayout`)** owns the logical grid; the cockpit scene owns the 3D positions and must name its marker nodes with the generated slot ids (`"<zone>_r<row>_c<col>"`, e.g. `main_r1_c3`).
- **12 slots in two zones:** `overhead` 1×4 (above the windshield) and `main` 2×4 (in front of the pilot). The windshield gap between them has no slots — it is what makes the panel read as a cockpit, and it forces the pilot to look in two places.
- A module declares `footprint` `[w,h]` and `zones` (which zones it may live in — a gear lever overhead reads as nonsense). `place(module_ids, seed)` is **seeded and deterministic**: biggest footprint first, ties broken on id, so a shared seed reproduces the whole flight *including the layout*. Returns `{placements, empty, unplaced}`.
- **Unfilled slots stay blank** (a plate). An early two-module mission looking almost empty is the intended difficulty tell.
- **Facts are NOT on slots.** `fact_anchors()` are fixed cockpit locations (`glareshield`, `yoke_tag`, `window_sticker`, `side_panel`) and each fact names one in its `display.anchor`. **Never place a fact placard beside the module that reads it** — that leaks the fact↔module association and gives away a large part of the puzzle. Same reason KTANE keeps edgework on the bomb's sides.
- **Camera = two tiers, KTANE-style** (focus the bomb / lean to the clock): *overview* shows which modules exist and the warning lights but not fine labels; *focus* tweens the camera above one module (~0.3s — that cost IS the pressure). Focus is a **camera move in 3D, never a fullscreen UI modal**: neighbours stay visible at the edges, timer and go-arounds stay on the HUD, or the panic is lost. Each slot gets a `FocusPoint` (camera position + look target); `footprint` sets the distance. Non-module props (fact placards, the LAND lever) are focus targets too. Tab cycles.
- This is what makes the information asymmetry **physical**: the pilot cannot see everything at once, so they must remember and describe. The camera enforces the core loop instead of a rule doing it.
- **Hands:** first-person seated pilot, hands/forearms only parented to the camera rig — a full IK body is barely visible from inside the head.

### Key decisions this session
- **Solo-first prototype**, on-screen manual. Networking (2-player split pilot/tower screens) deferred until the loop is proven fun.
- **Central store = the brain's facts, read by name.** No scattered global getters. Rules (data) reference facts by name; only display nodes read a fact through the brain. Reads are safe; scattered mutable global state is the thing to avoid.
- **No difficulty budget / cost / tier system.** Considered and rejected: stay literally on the KTANE model — hand-authored missions naming module ids, difficulty emerging from which types × how many.
- **No punitive surprises.** A failed LAND costs a life only. Anything a mode changes is shown before the round starts. The clock is the pressure; nothing else deducts silently.
- **Raw CSG placeholders** for all geometry; art last (the art direction — chunky low-poly, readability-first — means the placeholder→final gap is small).
- **Restart discipline** (see MCP rules above): clean quit only, never force-kill, never two instances.

### Milestones done
A′ data-layer + C# brain · B round loop (scenario→manual→timer→LAND→result) · C information-asymmetry puzzle · scene flow (menu/settings/recap) · decision-list manual engine (data-driven) · **module registry + campaign/mission/modes data layer** (`data/facts.gd`, `data/ops.gd`, `data/modules/*`, `data/module_registry.gd`, `data/dashboard.gd`, `data/campaign.gd`, `data/modes.gd` — data only, not yet wired into the round).

### Next (roadmap)
1. **Wire the data layer into the round** — `cockpit_manager.gd` takes a mission + mode instead of `CockpitManual.data()`: `ModuleRegistry.build_manual_data(mission.modules)` → brain; clock/lives from `CockpitModes.effective_*`. Then delete `data/manual.gd`.
2. **C# batch (one rebuild, one restart):** module check strategies (`state_match` / `value_match` + `{id, ok, expected, actual}` results) · `AttemptLand()` owning the lives counter and returning `LANDED`/`GO_AROUND`/`CRASHED` · `SelfTest()` coverage for the go-around path. Front-load everything here — batch it.
3. **Modular prefab cockpit + spawner + slot grid** — each module type is its own prefab scene; the cockpit holds slot markers with footprints; the spawner instantiates the mission's modules and leaves the rest **blank**. Turns the fixed cockpit into the procedural, difficulty-signalling dashboard.
4. Mission select + campaign progression UI; per-mission recap with the full module breakdown.
5. Complex module types (destination entry, coordinate calculation) — by then, registry entries with a `value_match` check and zero engine change.
6. Failure events (stuck / inverted / lying-indicator controls) — implement in the input→state pipeline (can be GDScript, no C# rebuild).
7. 2-player networking (host-client P2P) + split screens + lobby — only after the loop is proven.
8. Auto-generated manuals from modules; more modules/facts (all data now).
- Keep an **`IDEAS.md`** backlog, tagged core/content/polish; implement core-affecting ideas early, park content/polish for the content phase.

### Cleanup
Leftover test assets to delete when convenient: `res://test_sphere.tscn`, `res://sphere_mesh.tres`.

---

# Core Concept

Two players.

## Pilot

- First-person view inside the cockpit.
- Can manipulate switches, buttons and levers.
- Cannot see outside.
- Has incomplete information.
- Must describe what they see.

## Control Tower

- Has the flight manual.
- Guides the pilot.
- Diagnoses failures.
- Chooses the correct procedures.
- Never sees the cockpit.

The gameplay loop is based on communication.

---

# Gameplay Loop

1. Generate a random emergency.
2. Generate the required cockpit configuration.
3. Generate random events.
4. Pilot manipulates the cockpit.
5. Tower follows the manual.
6. Timer reaches zero (or checklist completed).
7. Pilot presses the **LAND** button.
8. Game validates every module.
9. Landing success or crash.

---

# Landing Logic

There is **no real-time flight simulation**.

The aircraft state is validated only at landing.

Example:

Required:

- Landing Gear DOWN
- Flaps 20°
- Radio 118.7
- Hydraulic Pressure OK
- Engine B OFF

If every required state is correct:

Landing succeeds.

Otherwise:

Crash.

This dramatically simplifies development while keeping tension high.

---

# Random Events

Examples:

- Engine fire
- Bird strike
- Hydraulic leak
- Electrical failure
- Frozen wings
- Radio interference
- Fuel leak
- Smoke in cockpit
- Instrument failure
- Turbulence
- Wrong indicator
- Stuck switch
- Delayed button response

Events modify existing modules instead of creating new mechanics.

---

# Modular Architecture

Everything is built from modules.

Example:

Landing Gear

- States
- Validation
- Possible failures

Radio

- Frequency
- Failures

Hydraulics

- Pressure
- Dependencies

Flaps

- Position
- Failures

etc.

The game assembles a scenario by combining modules.

This allows huge replayability with very little content creation.

---

# Manual

The manual is the heart of the game.

The Control Tower receives procedures such as:

Engine Fire

1. Cut engine B
2. Open Panel C
3. Check hydraulic pressure
4. Set flaps to 20
5. Confirm radio frequency

Decision trees:

IF warning light is RED

→ Procedure A

ELSE

→ Procedure B

The long-term goal is to generate manuals automatically from modules.

---

# Optional Modes

## Solo

The player controls the cockpit.

The manual is provided as a PDF.

Can be viewed:

- Second monitor
- Tablet
- Printed

Allows playing without requiring another game owner.

---

## Three Players

Pilot

Copilot

Control Tower

Possible Copilot responsibilities:

- Read instruments
- Confirm checklist
- Repair failures
- Handle secondary systems

---

# Mutators

Optional modifiers:

- Blind
- Mute
- Deaf
- Radio interference
- Cockpit layout changes
- Random control inversion
- Extra failures

Purely for replayability.

---

# Tone

The game is stressful but funny.

Not realistic.

Examples:

- Coffee spills
- Bottle rolling in cockpit
- Radio cutting
- Cat walking across dashboard
- Pilot distracted
- Ridiculous announcements

Comedy comes from panic.

---

# Crash

No expensive crash cinematic.

Player presses LAND.

Black screen.

Crash sound.

Silence.

Failure message.

Example:

"The investigation board thanks your crew for its contribution to aviation safety."

Cheap to produce.
Memorable.

---

# Victory

Landing notification "ding".

Cabin announcement.

Performance-based ending.

Examples:

Perfect:

"Welcome to your destination."

Average:

"Some passengers would appreciate a smoother landing next time."

Barely survived:

"Everyone survived. The luggage did not."

---

# Artistic Direction

Stylized.

Low poly.

Bright colors.

Readable.

Inspired by:

- RV There Yet?
- Keep Talking and Nobody Explodes
- Overcooked
- Untitled Goose Game

Characteristics:

- Chunky shapes
- Big colorful switches
- Warm lighting
- Dynamic warning lights
- Light bloom
- Slight camera shake
- Smoke particles
- Sparks
- Cartoon effects

Avoid realistic flight simulator visuals.

Readability first.

---

# Technical Direction

Engine:

Godot 4

Networking:

Host-client (P2P)

One player hosts.

No dedicated server.

Steam features:

- Lobby
- Friend invites
- Achievements
- Optional Cloud Save

---

# Development Philosophy

Build in layers.

## Phase 1 — Foundation

- Multiplayer
- Lobby
- Cockpit interaction
- Modular system
- Event system
- Manual system
- Landing validation

No polish.

Everything ugly but functional.

---

## Phase 2 — Content

Add modules.

Add events.

Add procedures.

Balance gameplay.

---

## Phase 3 — Visual Polish

Lighting.

Particles.

Animations.

Sound effects.

Voice lines.

UI.

---

## Phase 4 — Steam Release

Achievements.

Trailer.

Steam page.

Marketing assets.

Playtests.

---

# Design Principles

Always prioritize:

- Communication
- Readability
- Funny failures
- Replayability through modularity
- Low production cost
- Strong streamer potential

Never prioritize:

- Realistic flight simulation
- Complex aircraft physics
- Large environments
- AAA graphics

---

# Elevator Pitch

> A cooperative cockpit emergency game where one player operates a failing aircraft while another follows a procedural manual from the control tower. Work together under pressure, configure the cockpit correctly, and press LAND. If everything is right, you survive. If not... black screen.
