class_name BaseCommand
extends RefCounted
## Base class for every simulated program. To add a command, drop a new
## script in res://scripts/commands/ that extends BaseCommand — the registry
## discovers it automatically. See docs/ADDING_COMMANDS.md.


func get_command_name() -> String:
	return ""


func get_aliases() -> Array:
	return []


## One line for `help`.
func get_summary() -> String:
	return ""


## Synopsis line for `man` and usage errors.
func get_usage() -> String:
	return get_command_name()


## Longer text for `man`. Keep it short and practical.
func get_manual() -> String:
	return get_summary()


## Used to group `help` output: basics, files, text, permissions, users, processes, system, shell.
func get_category() -> String:
	return "misc"


## Returns the exit status (0 = success).
func execute(_ctx: CommandContext) -> int:
	return 0


func usage_error(ctx: CommandContext, message: String = "") -> int:
	if message != "":
		ctx.err("%s: %s\n" % [ctx.command_name(), message])
	ctx.err("Usage: %s\n" % get_usage())
	return 2


## getopt-style parsing.
##   value_short: short options that take a value, e.g. "nd" for -n 5 / -d,
##   value_long:  long options that take a value, e.g. ["lines"].
## Returns {"flags": {char|long: true}, "values": {opt: String}, "operands": [], "error": ""}
static func parse_options(args: Array, value_short: String = "", value_long: Array = []) -> Dictionary:
	var flags := {}
	var values := {}
	var operands: Array = []
	var i := 0
	var only_operands := false
	while i < args.size():
		var a: String = args[i]
		if only_operands or a == "-" or not a.begins_with("-") or a.length() == 1:
			operands.append(a)
			i += 1
			continue
		if a == "--":
			only_operands = true
			i += 1
			continue
		if a.begins_with("--"):
			var body := a.substr(2)
			var eq := body.find("=")
			if eq != -1:
				values[body.substr(0, eq)] = body.substr(eq + 1)
				flags[body.substr(0, eq)] = true
			elif body in value_long:
				if i + 1 >= args.size():
					return {"flags": flags, "values": values, "operands": operands, "error": "option '--%s' requires an argument" % body}
				values[body] = args[i + 1]
				flags[body] = true
				i += 1
			else:
				flags[body] = true
			i += 1
			continue
		# cluster of short flags: -la, -n5, -n 5
		var j := 1
		while j < a.length():
			var ch := a[j]
			if value_short.contains(ch):
				var rest := a.substr(j + 1)
				if rest != "":
					values[ch] = rest
				elif i + 1 < args.size():
					values[ch] = args[i + 1]
					i += 1
				else:
					return {"flags": flags, "values": values, "operands": operands, "error": "option requires an argument -- '%s'" % ch}
				flags[ch] = true
				break
			flags[ch] = true
			j += 1
		i += 1
	return {"flags": flags, "values": values, "operands": operands, "error": ""}
