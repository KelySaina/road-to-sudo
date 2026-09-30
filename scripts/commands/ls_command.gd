class_name LsCommand
extends BaseCommand


func get_command_name() -> String: return "ls"
func get_aliases() -> Array: return ["dir"]
func get_category() -> String: return "basics"
func get_summary() -> String: return "list directory contents"
func get_usage() -> String: return "ls [-a] [-l] [-h] [-R] [-d] [-1] [FILE...]"
func get_manual() -> String:
	return """Lists files. Useful options:
  -a   show hidden entries (names starting with '.')
  -l   long format: permissions, owner, group, size, date
  -h   human-readable sizes (with -l)
  -R   recurse into subdirectories
  -d   list a directory itself, not its contents
Reading -l:  -rwxr-x---  = type, then rwx for owner, group, others."""


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var f: Dictionary = opts.flags
	var cfg := {
		"all": f.has("a") or f.has("all"),
		"almost_all": f.has("A") or f.has("almost-all"),
		"long": f.has("l"),
		"human": f.has("h") or f.has("human-readable"),
		"recursive": f.has("R") or f.has("recursive"),
		"one": f.has("1") or not ctx.to_screen,
		"dir_itself": f.has("d"),
	}
	var targets: Array = opts.operands if not opts.operands.is_empty() else ["."]
	var files: Array = []
	var dirs: Array = []
	var code := 0
	for t in targets:
		var res := ctx.vfs().lookup(ctx.resolve(t), ctx.access())
		if not res.ok:
			ctx.fail("cannot access '%s'" % t, res.error)
			code = 2
			continue
		if res.node.is_dir() and not cfg.dir_itself:
			dirs.append(t)
		else:
			files.append({"label": t, "node": res.node})

	if not files.is_empty():
		_print_entries(ctx, files, cfg, false)
	var show_headers: bool = targets.size() > 1 or cfg.recursive
	for i in dirs.size():
		if show_headers and (i > 0 or not files.is_empty()):
			ctx.out("\n")
		if not _list_directory(ctx, dirs[i], cfg, show_headers):
			code = 2
	ctx.emit("listed", {"targets": targets, "all": cfg.all or cfg.almost_all, "long": cfg.long})
	return code


func _list_directory(ctx: CommandContext, label: String, cfg: Dictionary, header: bool) -> bool:
	var abs_path := ctx.resolve(label)
	var res := ctx.vfs().list_dir(abs_path, ctx.access())
	if header:
		ctx.out(label + ":\n", "header")
	if not res.ok:
		ctx.fail("cannot open directory '%s'" % label, res.error)
		return false
	var entries: Array = []
	if cfg.all:
		entries.append({"label": ".", "node": res.node})
		var parent := ctx.vfs().get_node_at(PathUtils.dirname(abs_path))
		entries.append({"label": "..", "node": parent if parent != null else res.node})
	for child_name in res.value:
		var child: VFSNode = res.node.children[child_name]
		if child.is_hidden() and not (cfg.all or cfg.almost_all):
			continue
		entries.append({"label": child_name, "node": child})
	_print_entries(ctx, entries, cfg, true)
	var ok := true
	if cfg.recursive:
		for e in entries:
			if e.label == "." or e.label == ".." or not e.node.is_dir():
				continue
			ctx.out("\n")
			var sub: String = label.trim_suffix("/") + "/" + e.label
			if not _list_directory(ctx, sub, cfg, true):
				ok = false
	return ok


func _print_entries(ctx: CommandContext, entries: Array, cfg: Dictionary, is_dir_listing: bool) -> void:
	if entries.is_empty():
		return
	if cfg.long:
		_print_long(ctx, entries, cfg, is_dir_listing)
		return
	for i in entries.size():
		var e: Dictionary = entries[i]
		ctx.out(e.label, _style_for(e.node))
		if cfg.one or i == entries.size() - 1:
			ctx.out("\n")
		else:
			ctx.out("  ")


func _print_long(ctx: CommandContext, entries: Array, cfg: Dictionary, is_dir_listing: bool) -> void:
	var rows: Array = []
	var w := {"links": 1, "owner": 1, "group": 1, "size": 1}
	var blocks := 0
	for e in entries:
		var node: VFSNode = e.node
		var links := 2 + _subdir_count(node) if node.is_dir() else 1
		var size_text := StringTools.human_size(node.size()) if cfg.human else str(node.size())
		blocks += int(ceil(node.size() / 4096.0)) * 4
		var row := {
			"mode": Permissions.to_symbolic(node.mode, node.kind_char()),
			"links": str(links), "owner": node.owner, "group": node.group,
			"size": size_text, "mtime": node.mtime, "label": e.label, "node": node,
		}
		for k in w:
			w[k] = maxi(w[k], row[k].length())
		rows.append(row)
	if is_dir_listing:
		ctx.out("total %d\n" % blocks, "dim")
	for r in rows:
		ctx.out("%s %s %s %s %s %s " % [
			r.mode, r.links.lpad(w.links), r.owner.rpad(w.owner), r.group.rpad(w.group), r.size.lpad(w.size), r.mtime,
		], "meta")
		ctx.out(r.label, _style_for(r.node))
		ctx.out("\n")


func _subdir_count(node: VFSNode) -> int:
	var n := 0
	for c in node.children.values():
		if c.is_dir():
			n += 1
	return n


func _style_for(node: VFSNode) -> String:
	if node.is_dir():
		return "dir"
	if (node.mode & 73) != 0:
		return "exec"
	if node.is_hidden():
		return "hidden"
	return ""
