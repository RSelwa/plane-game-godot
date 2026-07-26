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
- **C# rebuilds disconnect the cloud link.** Any `dotnet build` that changes the assembly makes the editor reload it and drop its cloud MCP connection. A clean `godot-cli close --force` + `open` + **~70s wait** auto-reconnects (no user action). So: FRONT-LOAD all C#, build rarely; do day-to-day work in GDScript/scenes/data which never disconnect.
- **Testing:** the running game's `print()` is unreadable via MCP, and `runtime-errors-get` needs C# runtime-capture init. Test pure logic by putting it in C# and calling it via `reflection-method-call` (e.g. `CockpitBrain.SelfTest()` static). GDScript runtime behavior (clicks, round flow) = user play-test. Verify structure via `scene-get-data`, compile via `script-validate`, visuals via `screenshot-viewport` (editor viewport renders CSG; `screenshot-camera` does NOT render CSG).

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
