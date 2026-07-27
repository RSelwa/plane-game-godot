## Ideas

Backlog. Tag each idea **core** (affects the engine/architecture — implement early),
**content** (new modules/facts/missions — the content phase), or **polish** (feel, art,
audio — last). Move an item to CLAUDE.md's roadmap when it becomes the next build.

### Module types
- **content** — Destination entry (FMC keypad): pilot types an airport code derived from facts. First `value_match` module.
- **content** — Coordinate calculation: tower computes lat/long from facts, pilot enters it. The "hard tier" module — high comms load, deliberately slow.
- **content** — Radio frequency: numeric dial, digits derived separately (e.g. integer part from one fact, decimal from another).
- **content** — Circuit breaker bank: several toggles, only the set matching a rule pulled. Multi-widget, one module.
- **content** — Fuel cross-feed: two-state module whose rule depends on the *arriving* airport, so it pairs badly (interestingly) with the lever.

### Difficulty levers (ranked, cheapest first — use these, not longer decision lists)
- **content** — Exotic operators over `eq`: `lastVowel`/`firstConsonant` force the pilot to spell aloud. Communication load *is* the difficulty.
- **content** — AND-arity: 2–3 conditions in one `when`, so the tower holds several facts at once.
- **content** — More states per module (a 5-position dial vs a 2-state switch).
- **core** — **Red herrings**: an optional `extra_facts` list on a mission generates facts no module reads. Pilot cannot tell what matters.
- **core** — **Cross-module dependencies**: a rule reads another module's *required* state (`{module: "switch", op: "eq", value: "ON"}`). Forces solve ordering, breaks parallel work between pilot and tower. The genuine KTANE-tier spike; needs the brain to resolve modules in dependency order and detect cycles.
- Explicitly rejected: deeper decision lists as a difficulty knob. A 6-branch list just makes the tower scroll — longer, not harder.

### Round / campaign
- **core** — Per-mission seed sharing ("replay mission m03 seed 4821") — the brain is already seed-deterministic, only needs surfacing.
- **content** — Star/rank per mission from attempts used + time left, feeding the existing victory-tier flavour text.
- **polish** — Go-around presentation: the LAND press that fails should *feel* like a go-around (engine spool, "GOING AROUND", altitude callout), not like an error dialog.
- **polish** — Mission-select screen shows the dashboard silhouette so the crew sees the module count grow across the campaign.

### Camera & interaction (the "large dashboard" problem)
KTANE's bomb is small enough to orbit and still read; a cockpit panel is not. At a framing
where the whole dashboard fits, nothing is legible — so free orbit fights the readability-first
principle. Decided direction: **two-tier camera**.
- **core** — Overview tier: whole panel, shows *which* modules exist + warning lights, deliberately NOT fine labels. Hover highlights, click / Enter focuses.
- **core** — Focus tier: camera tweens above one module, ~0.3s. That transition cost IS the pressure — the pilot cannot glance everywhere for free. Instant removes the spatial tension; a full second is just annoying.
- **core** — Focus must be a **camera move in 3D, never a fullscreen UI modal**. Neighbouring panels stay visible at the screen edges, timer + go-arounds pinned to the HUD. Lose peripheral awareness and the panic goes with it.
- **core** — This makes the information asymmetry *physical*: the pilot literally cannot see everything at once, so they must remember and describe. The camera enforces the core loop instead of a rule doing it.
- **core** — Slot `FocusPoint` (Node3D: camera position + look target) per dashboard slot; the spawner already places modules into slots, so focus anchors come free. `footprint` sets the camera distance (a 2×1 panel pulls back further than a 1×1 switch).
- **core** — Tab cycles modules. Faster than mouse-hunting, and it is the accessibility path the blind/mute mutators will need.
- **polish** — Slight DoF / FOV shift so the focused module reads crisp against a soft periphery.
- **core (DECIDED)** — Framing both zones: overview is a **seated free-look with clamped pitch/yaw**, not a fixed shot. The pilot glances up for the overhead zone and loses sight of the main panel while doing it — the glance is the tension. Start ≈ −25°/+35° pitch, ±35° yaw, tuned from a screenshot; clamps are camera-rig export vars. The overhead panel is then only tilted *less steep than real*, not faked flat. Exiting focus restores the previous look direction; Tab cycling swings the head so keyboard and mouse agree.
- **polish** — Tune whether the look-up needs a tiny head-bob / neck-strain cue so the cost of glancing up is felt, not just seen.

### Hands & body
- **core** — Hands/forearms only, parented to the camera rig, reaching the focused module's interaction point. A full IK seated body costs a lot and is barely visible from inside the pilot's head.
- **content** — **One hand occupied** as a real mechanic: holding coffee or a cigarette blocks two-hand actions, so the pilot must put it down. Comedy that is also a rule.
- **polish** — Idle hand business: tapping, cigarette ash, flinching on a warning light.

### Community content / modding (long-term, but decide the seam early)
- **core** — **Architectural warning:** the current data layer is GDScript `class_name` files compiled into the project, which is great for typo-safety and terrible for modding — a player cannot add one. Keep the built-in modules as they are, but plan for `ModuleRegistry.defs()` to **merge two sources**: compiled built-ins + module packs scanned at runtime. Deciding this before the registry has many callers is cheap; retrofitting it later is not.
- **core** — A module pack = a folder with a data file (JSON or `.tres`, runtime-loadable — not `.gd`), a `.tscn` prefab, and a manual section. Same fields the built-in defs use, so the pack format is just the def shape serialised.
- **core** — Packs must be validated on load with the existing `ModuleRegistry.validate()` rules and **fail loudly and individually** — one broken community module must not take down the registry.
- **content** — Community *missions* are the easier first step (a mission is only ids + time + lives) and would ship long before community *modules*.
- **content** — Steam Workshop for module packs and mission packs; a "verified/rated" flag so the campaign only draws from sane content.
- **content** — Mission/seed sharing codes as the zero-infrastructure version of community content.
- **polish** — In-game module authoring preview (spawn one module, roll facts, read the derived answer) — also the fastest internal authoring tool, so build it for ourselves first.

### Mutators (post-loop)
- **content** — Blind / mute / deaf, radio interference, random control inversion (see the design doc's mutator list). All are pure modifiers, so they slot next to `data/modes.gd` rather than into missions.

### Tone / comedy
- **polish** — Cabin PA announcements on success, tiered by performance.
- **polish** — Cockpit distractions that cost attention but never state: coffee spill, rolling bottle, cat on the dashboard.
