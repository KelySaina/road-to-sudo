class_name TreeCommand
extends BaseCommand


func get_command_name() -> String: return "tree"
func get_category() -> String: return "files"
func get_summary() -> String: return "draw a directory tree"
func get_usage() -> String: return "tree [-a] [-d] [-L LEVEL] [DIR]"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args(), "L")
	var target: String = "." if opts.operands.is_empty() else opts.operands[0]
	var res := ctx.vfs().lookup(ctx.resolve(target), ctx.access())
	if not res.ok:
		return ctx.fail(target, res.error)
	var cfg := {
		"all": opts.flags.has("a"),
		"dirs_only": opts.flags.has("d"),
		"max": int(opts.values.get("L", "64")),
		"dirs": 0,
		"files": 0,
	}
	ctx.out(target + "\n", "dir")
	_draw(ctx, res.node, "", 1, cfg)
	ctx.out("\n%d director%s, %d file%s\n" % [cfg.dirs, "y" if cfg.dirs == 1 else "ies", cfg.files, "" if cfg.files == 1 else "s"])
	return 0


func _draw(ctx: CommandContext, node: VFSNode, prefix: String, level: int, cfg: Dictionary) -> void:
	if level > cfg.max or not node.is_dir():
		return
	if not Permissions.can(node, ctx.access(), Permissions.READ):
		ctx.out(prefix + "└── [error opening dir]\n", "dim")
		return
	var names: Array = []
	for n in node.sorted_child_names():
		var child: VFSNode = node.children[n]
		if child.is_hidden() and not cfg.all:
			continue
		if cfg.dirs_only and not child.is_dir():
			continue
		names.append(n)
	for i in names.size():
		var child: VFSNode = node.children[names[i]]
		var last: bool = i == names.size() - 1
		ctx.out(prefix + ("└── " if last else "├── "), "dim")
		var style := "dir" if child.is_dir() else ("exec" if (child.mode & 73) != 0 else "")
		ctx.out(names[i] + "\n", style)
		if child.is_dir():
			cfg.dirs += 1
			_draw(ctx, child, prefix + ("    " if last else "│   "), level + 1, cfg)
		else:
			cfg.files += 1
