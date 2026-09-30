class_name FalseCommand
extends BaseCommand


func get_command_name() -> String: return "false"
func get_category() -> String: return "shell"
func get_summary() -> String: return "do nothing, unsuccessfully (exit status 1)"


func execute(_ctx: CommandContext) -> int:
	return 1
