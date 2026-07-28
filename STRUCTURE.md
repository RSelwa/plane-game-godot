# Project structure

## The three layers

| Layer | Lives in | Language | Job |
|---|---|---|---|
| **Brain (logic)** | `scripts/core/cockpit_brain.gd` | GDScript | The authoritative rules engine: control states, derived required config, facts, manual, landing validation |
| **Views (presentation)** | `scripts/*.gd` + `scenes/*.tscn` | GDScript | What the player sees and clicks. Owns no game truth, reads/writes it through the brain |
| **Data (content)** | `data/*.gd` | GDScript | Facts, ops, modules, dashboard, campaign, modes. Pure data, hot-reloads |

Everything is GDScript now. There is no C# and no MCP addon (removed). The game runs on a standard Godot build.

---

## How the CockpitBrain works

`CockpitBrain` (`scripts/core/cockpit_brain.gd`) is a `Node` with `class_name CockpitBrain`. One instance lives in a scene (the `Brain` node in `flight.tscn`). It holds four things for the current round:

1. **Controls** — for each control id: its state labels, its current state (`_state`), and its derived required state (`_required`).
2. **Facts** — the edgework the pilot reads aloud (warning light, airports, flight number). Rolled from the seed.
3. **Manual** — per-module ordered decision lists (`if / else-if / else`) loaded from the data layer.
4. **Validation** — `is_valid()` compares every control's current state against its required state.

### Where the required config comes from
It is **never stored as content**. It is *derived* every round:

```
generate_flight(seed)
  ├── roll every fact from the seed          (starting_airport = "BCN", flight_number = "4821", ...)
  └── for each module, walk its decision list top-to-bottom
        first branch whose conditions all pass  -> that control's required state
        a final "else" is the default
```

Same seed in => same facts => same required config. Fully reproducible.

### The condition engine
A condition is `{fact, op, value?}`. Ops: `eq neq starts ends contains firstVowel lastVowel firstConsonant lastConsonant even odd`. `Y` counts as a vowel. Multiple conditions in one branch are ANDed. `load_manual_json` validates the whole manual up front: a typo'd fact, control, op, or state label is reported as an error, not a silently broken round.

---

## Is the brain a "store" all modules share?

**Yes for one round, no for the whole game.** Precise version:

- The brain **is** the central store of a single round's truth. Modules (the view scripts) do **not** talk to each other. A click on a control does not reach into another control. Everything goes through the brain:
  - control click -> `request_cycle(id)` -> brain updates that control's state -> brain emits `state_changed` -> the view redraws.
  - The **facts** are the shared read-only data: a module's *rules* reference a fact by name (`starting_airport`, `flight_number`), and only the brain holds the rolled value. That is the "shared information" channel, and it is read-only to the modules.

- The brain is **not** a persistent global that survives across rounds or scenes. Its scope is one round. It is reset every round by `load_manual_json(...)` + `generate_flight(seed)`. Close the flight scene and the brain instance is gone.

- Cross-scene / cross-round persistence is a **different object**: the `Game` autoload (`scripts/game.gd`). That singleton survives scene changes and carries `last_result` from the flight scene to the recap scene. If you ever need data to live across the whole game session (campaign progress, unlocked missions), it goes in `Game`, not in the brain.

So: **brain = the single source of truth for the current round's modules; `Game` autoload = the thing that persists across the game.** Modules share information only by reading facts from the brain, never by reaching into each other.

---

## Data flow of one control click

```
player clicks a control (StaticBody3D, cockpit_control.gd)
  -> emits signal  cycle_requested(id)
  -> flight.gd catches it
  -> brain.request_cycle(id)              (brain is the authority; it decides the new state)
  -> brain emits  state_changed(id, new_state)
  -> manager calls control.apply_state(new_state)   (the view tilts its handle)
```

The view holds no canonical state. It is a pure function of the state pushed down to it. This is the seam that later lets a networked peer render a control from replicated state.

---

## Round lifecycle (flight.gd)

```
_ready()
  ├── spawn the mission's modules onto dashboard slots (module_spawner.gd)
  ├── register each spawned control with the brain
  ├── build the manual payload from the data layer and load_manual_json it into the brain
  ├── generate_flight(seed)   -> facts rolled, required config derived
  └── start the timer
_process(delta)
  └── count the clock down; at zero -> attempt land (crash)
LAND pressed
  └── brain.is_valid() -> LANDED / GO_AROUND / CRASHED, snapshot rows into Game.last_result, go to recap
```

---

## Public API of the brain

Controls: `register_control(id, labels)`, `request_cycle(id)`, `set_state(id, n)`, `get_state(id)`, `num_states(id)`, `state_label(id, n)`, `label_index(id, label)`.

Required config: `set_required(id, n)`, `clear_required()`, `has_required(id)`, `required_state(id)`, `is_valid()`.

Facts: `fact_ids()`, `fact_value(id)`.

Manual + flight: `load_manual_json(json) -> "OK" | errors`, `manual_ok()`, `generate_flight(seed)`, `manual_text()`.

Signal: `state_changed(id, state)`.

Test: `CockpitBrain.self_test()` (static) returns a `SELFTEST PASS/FAIL :: ...` report. Run headless via `scripts/tests/brain_test.gd`.

---

## Testing

The brain's logic is covered by `CockpitBrain.self_test()`: validation, decision-list derivation with real predicates, and the manual validator catching a rule that names a missing control. Run it without opening the editor:

```
<godot-binary> --headless --script res://scripts/tests/brain_test.gd
```

Exit code 0 = PASS, 1 = FAIL. This is the deterministic gate; the game's click/round behavior still needs a play-test.
