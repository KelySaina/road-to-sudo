class_name WhichCommand
extends BaseCommand


func get_command_name() -> String: return "which"
func get_category() -> String: return "shell"
func get_summary() -> String: return "locate a command's program file"
func get_usage() -> String: return "which COMMAND..."
func get_manual() -> String:
	return "Searches the directories in $PATH, in order, and prints the first match.\nThat is how the shell decides what `ls` actually runs."


func execute(ctx: CommandContext) -> int:
	var code := 0
	for a in ctx.args():
		var found := ""
		for dir in str(ctx.session.env.get("PATH", "")).split(":", false):
			var candidate := PathUtils.join(dir, a)
			var node := ctx.vfs().get_node_at(candidate)
			if node != null and not node.is_dir() and (node.mode & 73) != 0:
				found = candidate
				break
		if found == "":
			code = 1
		else:
			ctx.out(found + "\n")
	return code
