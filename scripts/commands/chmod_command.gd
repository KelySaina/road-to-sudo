class_name ChmodCommand
extends BaseCommand

static var _mode_regex: RegEx


func get_command_name() -> String: return "chmod"
func get_category() -> String: return "permissions"
func get_summary() -> String: return "change file permission bits"
func get_usage() -> String: return "chmod [-R] [-v] MODE FILE..."
func get_manual() -> String:
	return """Changes who may read (r), write (w) or execute (x) a file.
Symbolic:  u=owner g=group o=others a=all, then + - =, then r w x
    chmod u+x run.sh      owner may execute
    chmod go-w notes.txt  group and others lose write
Octal: each digit is r=4 + w=2 + x=1, for owner/group/others
    chmod 755 run.sh      rwxr-xr-x
    chmod 640 secret.txt  rw-r-----
Only the file's owner (or root) may change its mode."""


func execute(ctx: CommandContext) -> int:
	if _mode_regex == null:
		_mode_regex = RegEx.create_from_string("^([ugoa]*[-+=][rwxX]*,?)+$|^[0-7]{3,4}$")
	var args := ctx.args()
	var recursive := false
	var verbose := false
	var mode_spec := ""
	var files: Array = []
	for a in args:
		var s: String = a
		if mode_spec == "" and _mode_regex.search(s) != null:
			mode_spec = s
		elif s == "-R" or s == "--recursive":
			recursive = true
		elif s == "-v":
			verbose = true
		else:
			files.append(s)
	if mode_spec == "":
		return usage_error(ctx, "missing operand")
	if files.is_empty():
		return usage_error(ctx, "missing operand after '%s'" % mode_spec)
	var code := 0
	for f in files:
		var abs_path := ctx.resolve(f)
		var res := ctx.vfs().lookup(abs_path, ctx.access())
		if not res.ok:
			code = ctx.fail("cannot access '%s'" % f, res.error)
			continue
		var targets: Array = [abs_path]
		if recursive and res.node.is_dir():
			targets = ctx.vfs().walk(abs_path).paths
		for path in targets:
			var node := ctx.vfs().get_node_at(path)
			if not ctx.access().is_root() and node.owner != ctx.session.user:
				code = ctx.fail("changing permissions of '%s'" % f, "Operation not permitted")
				continue
			var new_mode := Permissions.apply_spec(node.mode, mode_spec.replace("X", "x"))
			if new_mode < 0:
				return ctx.fail("", "invalid mode: '%s'" % mode_spec)
			var old_mode := node.mode
			node.mode = new_mode
			if verbose:
				ctx.out("mode of '%s' changed from %s (%s) to %s (%s)\n" % [f,
					Permissions.to_octal(old_mode).lpad(4, "0"), Permissions.to_symbolic(old_mode).substr(1),
					Permissions.to_octal(new_mode).lpad(4, "0"), Permissions.to_symbolic(new_mode).substr(1)])
			ctx.emit("mode_changed", {"path": path, "old": old_mode, "new": new_mode})
	return code
