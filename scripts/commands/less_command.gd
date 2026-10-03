class_name LessCommand
extends BaseCommand
## An interactive pager. At the terminal it opens a full-screen, scrollable view
## (arrows/Space/b to move, g/G for top/bottom, / to search, q to quit). In a pipe
## or a redirect — where there's no screen to page on — it just prints the text,
## so `less big.log | grep x` still works. See scripts/ui/pager.gd.


func get_command_name() -> String: return "less"
func get_aliases() -> Array: return ["more"]
func get_category() -> String: return "files"
func get_summary() -> String: return "page through a file (scroll, search, q to quit)"
func get_usage() -> String: return "less FILE"
func get_manual() -> String:
	return """A pager for long files. At the terminal:
  ↑ ↓ / j k    scroll a line        Space / b    page down / up
  g / G        jump to top / bottom   / text       search, n for the next hit
  q            quit
In a pipe or redirect the file is printed in full instead, so you can still
`less file | grep ...`."""


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.error != "":
		return usage_error(ctx, opts.error)
	if opts.operands.is_empty() and not ctx.has_stdin:
		return usage_error(ctx, "missing filename")

	var read := ctx.read_sources(opts.operands)
	var multi: bool = read.sources.size() > 1
	var buf := ""
	for i in read.sources.size():
		var src: Dictionary = read.sources[i]
		if multi:
			buf += "%s==> %s <==\n" % ["\n" if i > 0 else "", src.name]
		buf += src.content
		if src.name != "-":
			ctx.emit("file_read", {"path": ctx.resolve(src.name)})

	# No screen to page on (piped or redirected): print it, like the old behaviour.
	if not ctx.to_screen:
		ctx.out(buf)
		return 1 if read.failed else 0

	if not read.sources.is_empty():
		var title := "(stdin)"
		if opts.operands.size() == 1 and str(opts.operands[0]) != "-":
			title = str(opts.operands[0])
		elif opts.operands.size() > 1:
			title = "%d files" % opts.operands.size()
		ctx.emit("open_pager", {"title": title, "content": buf})
	return 1 if read.failed else 0
