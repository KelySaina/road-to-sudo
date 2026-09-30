class_name AdvMapCommand
extends BaseCommand
## Adventure verb: show the places you have discovered.


func get_command_name() -> String: return "map"
func get_category() -> String: return "adventure"
func get_summary() -> String: return "show the world map (adventure)"
func get_usage() -> String: return "map"


func execute(ctx: CommandContext) -> int:
	var adv = ctx.session.adventure
	if adv == null:
		ctx.err("map: no map here. (You are not on an adventure.)\n")
		return 1
	ctx.out(adv.map_text())
	return 0
