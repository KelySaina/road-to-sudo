class_name AdvLookCommand
extends BaseCommand
## Adventure verb: survey your surroundings. See scripts/adventure/.


func get_command_name() -> String: return "look"
func get_aliases() -> Array: return ["l", "examine"]
func get_category() -> String: return "adventure"
func get_summary() -> String: return "survey your surroundings (adventure)"
func get_usage() -> String: return "look"
func get_manual() -> String:
	return "Describes where you are, who is here and where you can go.\nAn adventure verb — it works while you are on a journey (Adventure mode)."


func execute(ctx: CommandContext) -> int:
	if ctx.session.adventure == null:
		ctx.err("look: you are not on an adventure. (Try `ls` to look at files.)\n")
		return 1
	ctx.emit("adv_look", {})
	return 0
