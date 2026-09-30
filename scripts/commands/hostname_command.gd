class_name HostnameCommand
extends BaseCommand


func get_command_name() -> String: return "hostname"
func get_category() -> String: return "system"
func get_summary() -> String: return "print the machine's name"


func execute(ctx: CommandContext) -> int:
	ctx.out(ctx.machine().hostname + "\n")
	return 0
