class_name AdvGoCommand
extends BaseCommand
## Adventure verb: travel to a connected location.


func get_command_name() -> String: return "go"
func get_aliases() -> Array: return ["travel", "move", "walk"]
func get_category() -> String: return "adventure"
func get_summary() -> String: return "travel to another location (adventure)"
func get_usage() -> String: return "go <direction | place>"
func get_manual() -> String:
	return "Moves you along a path, e.g. `go north` or `go swamp`.\nWith no argument it lists the exits. You can't leave a fight unfinished."


func execute(ctx: CommandContext) -> int:
	var adv = ctx.session.adventure
	if adv == null:
		ctx.err("go: you are not on an adventure. (To change directory, use `cd`.)\n")
		return 1
	ctx.emit("adv_move", {"exit": " ".join(PackedStringArray(ctx.args()))})
	return 0
