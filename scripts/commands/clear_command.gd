class_name ClearCommand
extends BaseCommand


func get_command_name() -> String: return "clear"
func get_category() -> String: return "basics"
func get_summary() -> String: return "clear the terminal screen (also Ctrl+L)"


func execute(ctx: CommandContext) -> int:
	ctx.outcome.clear_screen = true
	return 0
