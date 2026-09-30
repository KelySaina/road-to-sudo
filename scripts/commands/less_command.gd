class_name LessCommand
extends CatCommand
## The real `less` is an interactive pager. Here it prints the whole file with
## a header, which keeps the habit (less for big files) without the modal UI.


func get_command_name() -> String: return "less"
func get_aliases() -> Array: return ["more"]
func get_summary() -> String: return "view a file (pager)"
func get_usage() -> String: return "less FILE"
func get_manual() -> String:
	return "A pager for long files. On a real system: arrows to scroll, / to search, q to quit.\nIn this simulator the file is printed in full; pipe into head/tail/grep to narrow it."


func execute(ctx: CommandContext) -> int:
	if ctx.to_screen and ctx.args().size() == 1:
		ctx.out("── %s ──\n" % ctx.args()[0], "dim")
	return super.execute(ctx)
