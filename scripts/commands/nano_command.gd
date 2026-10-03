class_name NanoCommand
extends BaseCommand
## A small but real text editor. Unlike the other programs, nano can't do its
## work in one synchronous call — it hands off to a full-screen editor overlay
## in the UI. The command only validates the target and emits `open_editor`;
## the UI opens the editor, and saving goes back through Game.apply_edit, which
## writes the file and re-grades the challenge. See scripts/ui/editor.gd.


func get_command_name() -> String: return "nano"
func get_aliases() -> Array: return ["edit"]
func get_category() -> String: return "text"
func get_summary() -> String: return "edit a text file in a full-screen editor"
func get_usage() -> String: return "nano FILE"
func get_manual() -> String:
	return """nano opens FILE in a simple full-screen editor.
  Type to edit.   ^O (Ctrl-O)  write the file out (save).
  ^X (Ctrl-X)  exit — it offers to save if you have unsaved changes.
  Esc          leave without saving.
If FILE doesn't exist yet, nano starts a new, empty buffer and creates it when
you save. Editing happens at the terminal, so nano can't be used in a pipe."""


func execute(ctx: CommandContext) -> int:
	var operands: Array = ctx.args()
	if operands.size() != 1:
		return usage_error(ctx, "expected exactly one file")
	if not ctx.to_screen:
		ctx.err("nano: can only edit at the terminal, not in a pipe or redirect\n")
		return 1

	var shown := str(operands[0])
	var path := ctx.resolve(shown)
	var vfs := ctx.vfs()
	var node := vfs.get_node_at(path)
	var content := ""
	var can_write := true

	if node != null:
		if node.is_dir():
			return ctx.fail(shown, "Is a directory")
		var res := vfs.read_file(path, ctx.access())
		if not res.ok:
			return ctx.fail(shown, res.error)
		content = res.value
		can_write = Permissions.can(node, ctx.access(), Permissions.WRITE)
	else:
		# A new file: the parent directory must exist and be writable to save.
		var parent := vfs.get_node_at(PathUtils.dirname(path))
		if parent == null or not parent.is_dir():
			return ctx.fail(shown, "No such file or directory")
		can_write = Permissions.can(parent, ctx.access(), Permissions.WRITE)

	ctx.emit("open_editor", {
		"path": path,
		"display": shown,
		"content": content,
		"can_write": can_write,
		"is_new": node == null,
	})
	return 0
