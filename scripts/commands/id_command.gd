class_name IdCommand
extends BaseCommand


func get_command_name() -> String: return "id"
func get_category() -> String: return "users"
func get_summary() -> String: return "print user and group IDs"
func get_usage() -> String: return "id [-u] [-g] [-G] [-n] [USER]"
func get_manual() -> String:
	return "Shows your numeric user id (uid), primary group (gid) and every group you belong to.\nuid 0 is root. Groups decide which 'group' permission bits apply to you."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var who: String = ctx.session.user if opts.operands.is_empty() else opts.operands[0]
	var m := ctx.machine()
	if not m.has_user(who):
		return ctx.fail("'%s'" % who, "no such user")
	var groups := m.groups_of(who)
	var primary := groups[0] if groups.size() > 0 else who
	var f: Dictionary = opts.flags
	if f.has("u"):
		ctx.out((who if f.has("n") else str(m.uid_of(who))) + "\n")
	elif f.has("g"):
		ctx.out((primary if f.has("n") else str(m.gid_of_group(primary))) + "\n")
	elif f.has("G"):
		var parts: Array = []
		for g in groups:
			parts.append(g if f.has("n") else str(m.gid_of_group(g)))
		ctx.out(" ".join(PackedStringArray(parts)) + "\n")
	else:
		var parts: Array = []
		for g in groups:
			parts.append("%d(%s)" % [m.gid_of_group(g), g])
		ctx.out("uid=%d(%s) gid=%d(%s) groups=%s\n" % [m.uid_of(who), who, m.gid_of_group(primary), primary, ",".join(PackedStringArray(parts))])
	ctx.emit("identity_checked", {"user": who})
	return 0
