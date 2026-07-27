class_name CockpitOps
extends RefCounted

## Condition operators understood by the C# brain (CockpitBrain.Condition.Eval).
## Declared once here so module rule files never spell an operator by hand.

const EQ := "eq"
const NEQ := "neq"
const STARTS := "starts"
const ENDS := "ends"
const CONTAINS := "contains"
const FIRST_VOWEL := "firstVowel"
const LAST_VOWEL := "lastVowel"          # note: Y counts as a vowel
const FIRST_CONSONANT := "firstConsonant"
const LAST_CONSONANT := "lastConsonant"
const EVEN := "even"
const ODD := "odd"

const ALL := [
	EQ, NEQ, STARTS, ENDS, CONTAINS,
	FIRST_VOWEL, LAST_VOWEL, FIRST_CONSONANT, LAST_CONSONANT,
	EVEN, ODD,
]

static func is_known(op: String) -> bool:
	return ALL.has(op)
