class_name DpkgCommand
extends BaseCommand
## The low-level package tool. Here it's read-only: query what's installed and
## at which version (apt is the everyday front-end for changes).


func get_command_name() -> String: return "dpkg"
func get_category() -> String: return "packages"
func get_summary() -> String: return "query installed packages and their versions"
func get_usage() -> String: return "dpkg -l [pattern] | dpkg -s PKG | dpkg -L PKG"
func get_manual() -> String:
	return """dpkg is the low-level package database behind apt.
  dpkg -l [pattern]   list installed packages (the leading 'ii' = installed ok)
  dpkg -s PKG         one package's status and version
  dpkg -L PKG         the files a package installed
It's the quickest way to answer 'is X installed, and which version?' — handy
for a security audit: `dpkg -l | grep openssl`."""


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	if args.is_empty():
		return usage_error(ctx, "need an option")
	var mode := ""
	var operands: Array = []
	for a in args:
		var s := str(a)
		match s:
			"-l", "--list": mode = "l"
			"-s", "--status": mode = "s"
			"-L", "--listfiles": mode = "L"
			_:
				if not s.begins_with("-"):
					operands.append(s)
	match mode:
		"l", "":
			return _list(ctx, operands)
		"s":
			return _status(ctx, operands)
		"L":
			return _listfiles(ctx, operands)
	return usage_error(ctx)


func _list(ctx: CommandContext, patterns: Array) -> int:
	var pkgs := ctx.machine().packages
	var names := pkgs.keys()
	names.sort()
	ctx.out("Desired=Unknown/Install/Remove/Purge/Hold\n", "dim")
	ctx.out("| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend\n", "dim")
	ctx.out("|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)\n", "dim")
	ctx.out("||/ Name                 Version          Description\n", "header")
	ctx.out("+++-====================-================-==========================================\n", "dim")
	for name in names:
		var p: Dictionary = pkgs[name]
		if not bool(p.installed):
			continue
		if not patterns.is_empty() and not _matches(name, patterns):
			continue
		ctx.out("ii  %s %s %s\n" % [str(name).rpad(20), str(p.version).rpad(16), p.description])
	return 0


func _status(ctx: CommandContext, names: Array) -> int:
	if names.is_empty():
		return usage_error(ctx, "-s needs a package name")
	var pkgs := ctx.machine().packages
	for name in names:
		if not pkgs.has(name) or not bool(pkgs[name].installed):
			ctx.err("dpkg-query: package '%s' is not installed and no information is available\n" % name)
			return 1
		var p: Dictionary = pkgs[name]
		ctx.out("Package: %s\n" % name, "header")
		ctx.out("Status: install ok installed\n")
		ctx.out("Version: %s\n" % p.version)
		ctx.out("Section: %s\n" % p.section)
		if not (p.depends as Array).is_empty():
			ctx.out("Depends: %s\n" % ", ".join(PackedStringArray(p.depends)))
		ctx.out("Description: %s\n" % p.description)
	return 0


func _listfiles(ctx: CommandContext, names: Array) -> int:
	if names.is_empty():
		return usage_error(ctx, "-L needs a package name")
	var pkgs := ctx.machine().packages
	for name in names:
		if not pkgs.has(name) or not bool(pkgs[name].installed):
			ctx.err("dpkg-query: package '%s' is not installed\n" % name)
			return 1
		for path in ["/.", "/usr", "/usr/bin/%s" % name, "/usr/share/doc/%s" % name, "/usr/share/doc/%s/copyright" % name]:
			ctx.out(path + "\n")
	return 0


func _matches(name: String, patterns: Array) -> bool:
	for pat in patterns:
		var p := str(pat)
		if p.contains("*"):
			if name.match(p):
				return true
		elif name.contains(p):
			return true
	return false
