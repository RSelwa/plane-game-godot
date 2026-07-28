class_name CockpitOps
extends RefCounted

## RE-EXPORT ONLY. Condition operator names, so module rule files never spell one by hand.
##
## Not a declaration: every value below points at ManualEngine, which is the single owner
## (name + behaviour + phrasing, all in its OPS table). Change an operator there and this
## file follows automatically. Content may depend on the engine; never the reverse.

const EQ := ManualEngine.EQ
const NEQ := ManualEngine.NEQ
const STARTS := ManualEngine.STARTS
const ENDS := ManualEngine.ENDS
const CONTAINS := ManualEngine.CONTAINS
const FIRST_VOWEL := ManualEngine.FIRST_VOWEL
const LAST_VOWEL := ManualEngine.LAST_VOWEL          # note: Y counts as a vowel
const FIRST_CONSONANT := ManualEngine.FIRST_CONSONANT
const LAST_CONSONANT := ManualEngine.LAST_CONSONANT
const EVEN := ManualEngine.EVEN
const ODD := ManualEngine.ODD

static func all() -> Array:
	return ManualEngine.op_names()

static func is_known(op: String) -> bool:
	return ManualEngine.has_op(op)
