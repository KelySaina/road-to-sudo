class_name TestCommand
extends BaseCommand
## Evaluate a condition — the workhorse behind `if` and `while`. Exit status 0
## means true, 1 means false. `[ ... ]` is the same command spelled with brackets.


func get_command_name() -> String: return "test"
func get_aliases() -> Array: return ["["]
func get_category() -> String: return "shell"
func get_summary() -> String: return "evaluate a condition (true = exit 0)"
func get_usage() -> String: return "test EXPR   |   [ EXPR ]"
func get_manual() -> String:
	return """Evaluate EXPR and exit 0 (true) or 1 (false). Used with if / while / && / ||.
Files:  -e PATH (exists)  -f (regular file)  -d (directory)  -r/-w/-x (readable/
        writable/executable)  -s (non-empty)
Strings: -z S (empty)  -n S (non-empty)  S1 = S2  S1 != S2
Numbers: N1 -eq -ne -lt -le -gt -ge N2
Negate with a leading `!`. Examples:
  test -f /etc/passwd   [ \"$USER\" = root ]   [ $count -gt 0 ]"""


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	if ctx.command_name() == "[":
		if args.is_empty() or str(args[-1]) != "]":
			ctx.err("[: missing `]'\n")
			return 2
		args = args.slice(0, args.size() - 1)
	var negate := false
	while not args.is_empty() and str(args[0]) == "!":
		negate = not negate
		args.pop_front()
	var result := _eval(ctx, args)
	if result == 2:
		return 2
	if negate:
		result = 1 - result
	return result


## Returns 0 (true), 1 (false) or 2 (error).
func _eval(ctx: CommandContext, args: Array) -> int:
	match args.size():
		0:
			return 1
		1:
			# A lone string is true when non-empty.
			return 0 if str(args[0]) != "" else 1
		2:
			return _unary(ctx, str(args[0]), str(args[1]))
		3:
			return _binary(str(args[0]), str(args[1]), str(args[2]))
		_:
			ctx.err("test: too many arguments\n")
			return 2


func _unary(ctx: CommandContext, op: String, operand: String) -> int:
	if op == "-z":
		return 0 if operand == "" else 1
	if op == "-n":
		return 0 if operand != "" else 1
	if op in ["-e", "-f", "-d", "-r", "-w", "-x", "-s"]:
		var node := ctx.vfs().get_node_at(ctx.resolve(operand))
		if node == null:
			return 1
		match op:
			"-e": return 0
			"-f": return 0 if not node.is_dir() else 1
			"-d": return 0 if node.is_dir() else 1
			"-s": return 0 if not node.is_dir() and node.content != "" else 1
			"-r": return 0 if Permissions.can(node, ctx.access(), Permissions.READ) else 1
			"-w": return 0 if Permissions.can(node, ctx.access(), Permissions.WRITE) else 1
			"-x": return 0 if Permissions.can(node, ctx.access(), Permissions.EXEC) else 1
	ctx.err("test: %s: unary operator expected\n" % op)
	return 2


func _binary(a: String, op: String, b: String) -> int:
	match op:
		"=", "==":
			return 0 if a == b else 1
		"!=":
			return 0 if a != b else 1
		"-eq", "-ne", "-lt", "-le", "-gt", "-ge":
			if not a.is_valid_int() or not b.is_valid_int():
				return 2
			var x := int(a)
			var y := int(b)
			match op:
				"-eq": return 0 if x == y else 1
				"-ne": return 0 if x != y else 1
				"-lt": return 0 if x < y else 1
				"-le": return 0 if x <= y else 1
				"-gt": return 0 if x > y else 1
				"-ge": return 0 if x >= y else 1
	return 2
