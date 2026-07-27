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

### Mutators (post-loop)
- **content** — Blind / mute / deaf, radio interference, random control inversion (see the design doc's mutator list). All are pure modifiers, so they slot next to `data/modes.gd` rather than into missions.

### Tone / comedy
- **polish** — Cabin PA announcements on success, tiered by performance.
- **polish** — Cockpit distractions that cost attention but never state: coffee spill, rolling bottle, cat on the dashboard.
