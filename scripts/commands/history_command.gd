class_name HistoryCommand
extends BaseCommand


func get_command_name() -> String: return "history"
func get_category() -> String: return "basics"
func get_summary() -> String: return "show previously typed commands"
func get_usage() -> String: return "history [-c] [N]"
func get_manual() -> String:
	return "Lists what you typed, oldest first. Handy for retracing your steps\nafter a mistake. -c clears the list. Arrow Up/Down recall commands at the prompt."


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	if args.has("-c"):
		ctx.session.history.clear()
		return 0
	var hist: Array = ctx.session.history
	var start := 0
	if not args.is_empty() and str(args[0]).is_valid_int():
		start = maxi(0, hist.size() - int(args[0]))
	for i in range(start, hist.size()):
		ctx.out("%5d  %s\n" % [i + 1, hist[i]])
	return 0
