class_name TrueCommand
extends BaseCommand


func get_command_name() -> String: return "true"
func get_category() -> String: return "shell"
func get_summary() -> String: return "do nothing, successfully (exit status 0)"


func execute(_ctx: CommandContext) -> int:
	return 0
