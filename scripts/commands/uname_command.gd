class_name UnameCommand
extends BaseCommand


func get_command_name() -> String: return "uname"
func get_category() -> String: return "system"
func get_summary() -> String: return "print system information"
func get_usage() -> String: return "uname [-a] [-s] [-n] [-r] [-m]"


func execute(ctx: CommandContext) -> int:
	var f: Dictionary = parse_options(ctx.args()).flags
	var info := {"s": "Linux", "n": ctx.machine().hostname, "r": "6.1.0-sudo", "v": "#1 SMP PREEMPT_DYNAMIC", "m": "x86_64", "o": "GNU/Linux"}
	if f.is_empty():
		ctx.out("Linux\n")
		return 0
	var parts: Array = []
	for k in ["s", "n", "r", "v", "m", "o"]:
		if f.has("a") or f.has(k):
			parts.append(info[k])
	ctx.out(" ".join(PackedStringArray(parts)) + "\n")
	return 0
