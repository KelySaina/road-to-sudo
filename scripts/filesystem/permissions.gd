class_name Permissions
extends RefCounted
## Unix permission bits: parsing, formatting and access checks.
## GDScript has no octal literals, so modes are built from strings ("755").

const READ := 4
const WRITE := 2
const EXEC := 1


static func from_octal(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return -1
	var value := 0
	for i in t.length():
		var code := t.unicode_at(i)
		if code < 48 or code > 55:
			return -1
		value = value * 8 + (code - 48)
	return value


static func to_octal(mode: int) -> String:
	var out := ""
	var m := mode & 4095
	for i in 4:
		out = str(m & 7) + out
		m >>= 3
	return out.trim_prefix("0") if out.begins_with("0") and out.length() > 3 else out


static func to_symbolic(mode: int, kind_char: String = "-") -> String:
	var chars := "rwxrwxrwx"
	var out := kind_char
	for i in 9:
		var bit := 1 << (8 - i)
		out += chars[i] if (mode & bit) != 0 else "-"
	return out


## Bits (0-7) that apply to this accessor for the given node.
static func effective_bits(node: VFSNode, access: AccessContext) -> int:
	if node.owner == access.user:
		return (node.mode >> 6) & 7
	if access.in_group(node.group):
		return (node.mode >> 3) & 7
	return node.mode & 7


static func can(node: VFSNode, access: AccessContext, want: int) -> bool:
	if access.is_root():
		# root ignores rwx, except that execute needs at least one x bit.
		if want == EXEC and not node.is_dir():
			return (node.mode & 73) != 0
		return true
	return (effective_bits(node, access) & want) == want


## Applies chmod-style specs: "755", "u+x", "go-w", "a=r", "+x", "u+x,g-w".
## Returns -1 on invalid spec.
static func apply_spec(mode: int, spec: String) -> int:
	var numeric := from_octal(spec)
	if numeric >= 0 and spec.length() <= 4:
		return numeric
	var result := mode
	for clause in spec.split(","):
		result = _apply_clause(result, clause)
		if result < 0:
			return -1
	return result


static func _apply_clause(mode: int, clause: String) -> int:
	var i := 0
	var who := ""
	while i < clause.length() and "ugoa".contains(clause[i]):
		who += clause[i]
		i += 1
	if who == "" or who.contains("a"):
		who = "ugo"
	if i >= clause.length() or not "+-=".contains(clause[i]):
		return -1
	var op := clause[i]
	i += 1
	var bits := 0
	while i < clause.length():
		match clause[i]:
			"r": bits |= READ
			"w": bits |= WRITE
			"x": bits |= EXEC
			_: return -1
		i += 1
	var result := mode
	for w in who:
		var shift := 6 if w == "u" else (3 if w == "g" else 0)
		match op:
			"+": result |= bits << shift
			"-": result &= ~(bits << shift)
			"=":
				result &= ~(7 << shift)
				result |= bits << shift
	return result
