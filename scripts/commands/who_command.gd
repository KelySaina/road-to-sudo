class_name WhoCommand
extends BaseCommand


func get_command_name() -> String: return "who"
func get_aliases() -> Array: return ["w"]
func get_category() -> String: return "users"
func get_summary() -> String: return "show who is logged in"
func get_usage() -> String: return "who"
func get_manual() -> String:
	return "Lists the users with an active login session (name, terminal, when).\n`whoami` is just YOU; `who` is everyone currently on the machine."


func execute(ctx: CommandContext) -> int:
	var m := ctx.machine()
	# Derive sessions from processes with a tty, plus the current shell.
	var seen := {}
	var rows: Array = [[ctx.session.user, "pts/0", "10:24"]]
	seen[ctx.session.user] = true
	for p in m.processes:
		var u: String = p.get("user", "")
		if p.get("tty", "") != "" and not seen.has(u) and u != "root":
			seen[u] = true
			rows.append([u, str(p.get("tty", "pts/1")), "09:%02d" % (int(p.pid) % 60)])
	for r in rows:
		ctx.out("%s %s        2026-06-05 %s\n" % [str(r[0]).rpad(10), r[1], r[2]])
	return 0
