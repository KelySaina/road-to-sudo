class_name UmaskCommand
extends BaseCommand


func get_command_name() -> String: return "umask"
func get_category() -> String: return "permissions"
func get_summary() -> String: return "show or set the default-permission mask"
func get_usage() -> String: return "umask [-S] [MODE]"
func get_manual() -> String:
	return """The umask decides the permissions NEW files and directories get. It's a
mask of bits to REMOVE from the defaults (666 for files, 777 for dirs).
  umask          show it (e.g. 0022)
  umask 077      new files become private to you (600 / 700)
So with umask 022, a new file is 666 - 022 = 644, a new dir 777 - 022 = 755."""


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.operands.is_empty():
		var m := ctx.session.umask
		if opts.flags.has("S"):
			ctx.out("u=%s,g=%s,o=%s\n" % [_sym((7 & ~(m >> 6))), _sym((7 & ~(m >> 3))), _sym((7 & ~m))])
		else:
			ctx.out("0%s\n" % Permissions.to_octal(m).lpad(3, "0"))
		return 0
	var value := Permissions.from_octal(str(opts.operands[0]))
	if value < 0:
		return ctx.fail("", "invalid mask '%s'" % opts.operands[0])
	ctx.session.umask = value
	return 0


func _sym(bits: int) -> String:
	var s := ""
	if bits & 4: s += "r"
	if bits & 2: s += "w"
	if bits & 1: s += "x"
	return s
