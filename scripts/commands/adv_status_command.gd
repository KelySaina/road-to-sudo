class_name AdvStatusCommand
extends BaseCommand
## Adventure verb: your health and the keys you carry.


func get_command_name() -> String: return "status"
func get_aliases() -> Array: return ["hp", "health"]
func get_category() -> String: return "adventure"
func get_summary() -> String: return "show your health and keys (adventure)"
func get_usage() -> String: return "status"


func execute(ctx: CommandContext) -> int:
	var adv = ctx.session.adventure
	if adv == null:
		ctx.err("status: nothing to report. (You are not on an adventure.)\n")
		return 1
	ctx.out(adv.status_text())
	return 0
