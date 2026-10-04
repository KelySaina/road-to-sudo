class_name Arith
extends RefCounted
## Shell arithmetic expansion: $(( expr )). A small integer evaluator with the
## usual C/bash operators and precedence, so `echo $(( (2+3) * 4 ))` prints 20
## and `i=$(( i + 1 ))` counts. Variables resolve through the session (bare `i`
## or `$i`), non-numbers read as 0, and division by zero yields 0 rather than
## crashing. Only integers, like real bash arithmetic.


## Replace every $(( ... )) in `line` with its value. Unbalanced ones are left
## as-is. Call before command substitution so `$((` isn't mistaken for `$(`.
static func expand(line: String, session: ShellSession) -> String:
	if not line.contains("$(("):
		return line
	var out := ""
	var i := 0
	var n := line.length()
	while i < n:
		var at := line.find("$((", i)
		if at == -1:
			out += line.substr(i)
			break
		out += line.substr(i, at - i)
		var depth := 2
		var k := at + 3
		while k < n and depth > 0:
			var c := line[k]
			if c == "(":
				depth += 1
			elif c == ")":
				depth -= 1
			k += 1
		if depth > 0:
			# Unbalanced — leave the rest untouched.
			out += line.substr(at)
			return out
		var expr := line.substr(at + 3, (k - 2) - (at + 3))
		out += str(eval(expr, session))
		i = k
	return out


## Evaluate one arithmetic expression to an int.
static func eval(expr: String, session: ShellSession) -> int:
	var tokens := _tokenize(expr)
	var p := {"t": tokens, "i": 0, "session": session}
	var v := _or(p)
	return v


# --- recursive descent (lowest precedence first) ----------------------------

static func _or(p: Dictionary) -> int:
	var a := _and(p)
	while _peek(p) == "||":
		_next(p)
		var b := _and(p)
		a = 1 if (a != 0 or b != 0) else 0
	return a


static func _and(p: Dictionary) -> int:
	var a := _cmp(p)
	while _peek(p) == "&&":
		_next(p)
		var b := _cmp(p)
		a = 1 if (a != 0 and b != 0) else 0
	return a


static func _cmp(p: Dictionary) -> int:
	var a := _add(p)
	while _peek(p) in ["==", "!=", "<", ">", "<=", ">="]:
		var op := _next(p)
		var b := _add(p)
		match op:
			"==": a = 1 if a == b else 0
			"!=": a = 1 if a != b else 0
			"<": a = 1 if a < b else 0
			">": a = 1 if a > b else 0
			"<=": a = 1 if a <= b else 0
			">=": a = 1 if a >= b else 0
	return a


static func _add(p: Dictionary) -> int:
	var a := _mul(p)
	while _peek(p) in ["+", "-"]:
		var op := _next(p)
		var b := _mul(p)
		a = a + b if op == "+" else a - b
	return a


static func _mul(p: Dictionary) -> int:
	var a := _unary(p)
	while _peek(p) in ["*", "/", "%"]:
		var op := _next(p)
		var b := _unary(p)
		match op:
			"*": a = a * b
			"/": a = 0 if b == 0 else a / b
			"%": a = 0 if b == 0 else a % b
	return a


static func _unary(p: Dictionary) -> int:
	var op := _peek(p)
	if op == "-":
		_next(p)
		return -_unary(p)
	if op == "+":
		_next(p)
		return _unary(p)
	if op == "!":
		_next(p)
		return 1 if _unary(p) == 0 else 0
	return _primary(p)


static func _primary(p: Dictionary) -> int:
	var tok := _next(p)
	if tok == "(":
		var v := _or(p)
		if _peek(p) == ")":
			_next(p)
		return v
	if tok == "":
		return 0
	if tok.is_valid_int():
		return int(tok)
	# A variable name (bare, or already stripped of $). Read it from the session.
	var name := tok.lstrip("$")
	var raw: String = p.session.get_variable(name).strip_edges()
	return int(raw) if raw.is_valid_int() else 0


# --- token helpers -----------------------------------------------------------

static func _peek(p: Dictionary) -> String:
	return p.t[p.i] if p.i < p.t.size() else ""


static func _next(p: Dictionary) -> String:
	var tok := _peek(p)
	p.i += 1
	return tok


static func _tokenize(expr: String) -> Array:
	var tokens: Array = []
	var i := 0
	var n := expr.length()
	const TWO := ["==", "!=", "<=", ">=", "&&", "||"]
	while i < n:
		var c := expr[i]
		if c == " " or c == "\t":
			i += 1
			continue
		if i + 1 < n and (c + expr[i + 1]) in TWO:
			tokens.append(c + expr[i + 1])
			i += 2
			continue
		if c in ["+", "-", "*", "/", "%", "(", ")", "<", ">", "!"]:
			tokens.append(c)
			i += 1
			continue
		# a run of word characters (digits, letters, _ , $) is one token
		var start := i
		while i < n and (expr[i].is_valid_identifier() or expr[i] == "$" or ("0" <= expr[i] and expr[i] <= "9")):
			i += 1
		if i == start:
			i += 1  # skip anything unexpected
		else:
			tokens.append(expr.substr(start, i - start))
	return tokens
