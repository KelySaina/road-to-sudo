class_name EchoCommand
extends BaseCommand


func get_command_name() -> String: return "echo"
func get_category() -> String: return "basics"
func get_summary() -> String: return "print text"
func get_usage() -> String: return "echo [-n] [-e] [TEXT...]"
func get_manual() -> String:
	return "Prints its arguments separated by spaces.\n  -n  no trailing newline\n  -e  interpret \\n and \\t\nCombine with > to write a file:  echo hello > greeting.txt"


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var newline := true
	var escapes := false
	while not args.is_empty() and args[0] in ["-n", "-e", "-E", "-ne", "-en"]:
		var a: String = args.pop_front()
		if a.contains("n"):
			newline = false
		if a.contains("e"):
			escapes = true
		if a == "-E":
			escapes = false
	var text := " ".join(PackedStringArray(args))
	if escapes:
		text = text.replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
	ctx.out(text + ("\n" if newline else ""))
	return 0
