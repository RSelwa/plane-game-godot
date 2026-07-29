class_name ModuleAirportCode
extends RefCounted

## AIRPORT CODE — the KTANE "Password" module. Three letter-wheels, six letters each.
## The pilot reads the eighteen letters aloud; the tower finds the ONE airport code from the
## manual's list those wheels can spell, and has the pilot dial it.
##
## Model B module. Its answer is NOT derived from a decision list over flight facts: it is
## SEARCHED — the wheels are the module's own per-instance edgework, rolled from the seed, and
## the answer is the single pool code they spell. This file owns that generation strategy.
##
## Each wheel is one control with WHEEL_SIZE states (its letters). The required state of wheel i
## is the index of the target's i-th letter on that wheel, so the generic `state_match` check
## validates the module with zero special-casing downstream — the only novelty is here, in how
## the required states are produced.

const ID := "airport_code"

const WHEEL_COUNT := 3
const WHEEL_SIZE := 6
const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

## Draw-check-repeat converges in ~1.5 tries on a real pool (measured, see WIP.md); this only
## guards against a degenerate pool that can never be made unique, so it stays high.
const MAX_ATTEMPTS := 2000

## The Model B contract for this type. `kind: "wheels"` marks it as a generated module (no
## decision list, prefab root is a Node3D of N wheels), so the registry validates it on its
## wheel fields rather than on states/rules. `max_instances` caps how many a round may draw.
static func def() -> Dictionary:
	return {
		"id": ID,
		"display": "AIRPORT CODE",
		"scene": "res://scenes/modules/airport_code.tscn",
		"footprint": [2, 1],
		"zones": [DashboardLayout.ZONE_MAIN],
		"kind": "wheels",
		"check": "state_match",
		"wheel_count": WHEEL_COUNT,
		"wheel_size": WHEEL_SIZE,
		"max_instances": 1,
		"edgework_gen": "airport_wheels",
	}

## Roll one board from `codes` and `rng`. Deterministic: same rng state + same pool => same
## board, which is what keeps a shared seed reproducing the whole flight. Returns
##   { target: String, wheels: [[6 letters] x WHEEL_COUNT], target_index: [i x WHEEL_COUNT],
##     start: [i x WHEEL_COUNT] }
## or an empty dictionary on failure (also pushed as an engine error).
static func generate(codes: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := _clean_pool(codes)
	if pool.is_empty():
		push_error("ModuleAirportCode: no usable %d-letter codes in pool" % WHEEL_COUNT)
		return {}
	for _attempt in MAX_ATTEMPTS:
		var target: String = pool[rng.randi_range(0, pool.size() - 1)]
		var wheels := _roll_wheels(target, rng)
		if _count_spellable(pool, wheels) != 1:
			continue
		var target_index := _target_index(target, wheels)
		return {
			"target": target,
			"wheels": wheels,
			"target_index": target_index,
			"start": _roll_start(target_index, rng),
		}
	push_error("ModuleAirportCode: no unique board after %d attempts" % MAX_ATTEMPTS)
	return {}

## A code is spellable when each of its letters sits on the matching wheel.
static func is_spellable(code: String, wheels: Array) -> bool:
	if code.length() != wheels.size():
		return false
	for i in wheels.size():
		if not (wheels[i] as Array).has(code[i]):
			return false
	return true

## Keep only usable codes: the right length, uppercased, deduplicated, in pool order.
static func _clean_pool(codes: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for c in codes:
		var s := str(c).to_upper()
		if s.length() != WHEEL_COUNT or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out

## One wheel per position: the target's letter for that position plus distinct random fillers,
## then shuffled so the answer is not always in the same slot.
static func _roll_wheels(target: String, rng: RandomNumberGenerator) -> Array:
	var wheels: Array = []
	for i in WHEEL_COUNT:
		var letters: Array = [target[i]]
		var guard := 0
		while letters.size() < WHEEL_SIZE and guard < 1000:
			guard += 1
			var ch := ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
			if not letters.has(ch):
				letters.append(ch)
		_shuffle(letters, rng)
		wheels.append(letters)
	return wheels

static func _count_spellable(pool: Array, wheels: Array) -> int:
	var n := 0
	for code in pool:
		if is_spellable(code, wheels):
			n += 1
	return n

static func _target_index(target: String, wheels: Array) -> Array:
	var idx: Array = []
	for i in WHEEL_COUNT:
		idx.append((wheels[i] as Array).find(target[i]))
	return idx

## Random starting rotation per wheel, never already on the solution.
static func _roll_start(target_index: Array, rng: RandomNumberGenerator) -> Array:
	var start: Array = []
	for i in WHEEL_COUNT:
		start.append(rng.randi_range(0, WHEEL_SIZE - 1))
	if start == target_index:
		var w := rng.randi_range(0, WHEEL_COUNT - 1)
		start[w] = (int(start[w]) + 1) % WHEEL_SIZE
	return start

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

## Deterministic gate: one board from a fixed seed, checked on every property the pipeline
## will rely on. Run from scripts/tests/brain_test.gd.
static func self_test() -> String:
	var log: Array = []
	var pool := ["OLY", "BCN", "LHR", "JFK", "CDG", "MAD"]

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var b := generate(pool, rng)

	var built := not b.is_empty()
	log.append("built=%s" % built)
	if not built:
		return "SELFTEST FAIL :: " + " | ".join(log)

	var count := _count_spellable(pool, b["wheels"])
	var unique := count == 1
	var target_spellable := is_spellable(b["target"], b["wheels"])
	log.append("unique(count=%d)=%s target_spellable=%s" % [count, unique, target_spellable])

	var idx_ok := true
	for i in WHEEL_COUNT:
		if b["wheels"][i][b["target_index"][i]] != b["target"][i]:
			idx_ok = false
	log.append("target_index_ok=%s" % idx_ok)

	var wheels_ok := true
	for w in b["wheels"]:
		if (w as Array).size() != WHEEL_SIZE:
			wheels_ok = false
		var seen: Dictionary = {}
		for ch in w:
			if seen.has(ch):
				wheels_ok = false
			seen[ch] = true
	log.append("wheels_shape_ok=%s" % wheels_ok)

	var not_solved: bool = b["start"] != b["target_index"]
	log.append("not_pre_solved=%s" % not_solved)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	var deterministic := generate(pool, rng2) == b
	log.append("deterministic=%s" % deterministic)

	var all_ok := built and unique and target_spellable and idx_ok and wheels_ok and not_solved and deterministic
	return ("SELFTEST PASS :: " if all_ok else "SELFTEST FAIL :: ") + " | ".join(log)
