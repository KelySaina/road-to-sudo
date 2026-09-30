class_name UnsetCommand
extends BaseCommand


func get_command_name() -> String: return "unset"
func get_category() -> String: return "shell"
func get_summary() -> String: return "remove a variable"
func get_usage() -> String: return "unset NAME..."


func execute(ctx: CommandContext) -> int:
	for a in ctx.args():
		ctx.session.env.erase(a)
	return 0
