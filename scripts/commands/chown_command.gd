class_name ChownCommand
extends BaseCommand


func get_command_name() -> String: return "chown"
func get_aliases() -> Array: return ["chgrp"]
func get_category() -> String: return "permissions"
func get_summary() -> String: return "change file owner and group"
func get_usage() -> String: return "chown [-R] OWNER[:GROUP] FILE...   |   chgrp GROUP FILE..."
func get_manual() -> String:
	return "Gives a file to another user and/or group.\n  chown alice report.txt        new owner\n  chown alice:devs report.txt   owner and group\n  chown :devs report.txt        group only (same as chgrp devs)\nOnly root may give files away. A normal user may only change the group\nof their own files to a group they belong to."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var ops: Array = opts.operands
	if ops.size() < 2:
		return usage_error(ctx, "missing operand")
	var spec: String = ops.pop_front()
	if ctx.command_name() == "chgrp":
		spec = ":" + spec
	var new_owner := spec.split(":")[0] if spec.contains(":") else spec
	var new_group := spec.split(":")[1] if spec.contains(":") else ""
	var m := ctx.machine()
	if new_owner != "" and not m.has_user(new_owner):
		return ctx.fail("", "invalid user: '%s'" % new_owner)
	if new_group != "" and not _group_exists(m, new_group):
		return ctx.fail("", "invalid group: '%s'" % new_group)
	var recursive: bool = opts.flags.has("R")
	var code := 0
	for f in ops:
		var abs_path := ctx.resolve(f)
		var res := ctx.vfs().lookup(abs_path, ctx.access())
		if not res.ok:
			code = ctx.fail("cannot access '%s'" % f, res.error)
			continue
		var targets: Array = ctx.vfs().walk(abs_path).paths if recursive else [abs_path]
		for path in targets:
			var node := ctx.vfs().get_node_at(path)
			if not _allowed(ctx, node, new_owner, new_group):
				code = ctx.fail("changing ownership of '%s'" % f, "Operation not permitted")
				break
			if new_owner != "":
				node.owner = new_owner
			if new_group != "":
				node.group = new_group
			ctx.emit("owner_changed", {"path": path, "owner": node.owner, "group": node.group})
	return code


func _allowed(ctx: CommandContext, node: VFSNode, new_owner: String, new_group: String) -> bool:
	if ctx.access().is_root():
		return true
	if node.owner != ctx.session.user:
		return false
	if new_owner != "" and new_owner != ctx.session.user:
		return false
	return new_group == "" or ctx.access().in_group(new_group)


func _group_exists(m: Machine, group: String) -> bool:
	for u in m.users.values():
		if group in u.get("groups", []):
			return true
	return false
