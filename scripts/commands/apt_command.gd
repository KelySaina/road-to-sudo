class_name AptCommand
extends BaseCommand
## A teaching subset of apt over the machine's package database. Reading
## (search/show/list) is open; changing the system (install/remove/update)
## needs root, like the real thing.


func get_command_name() -> String: return "apt"
func get_category() -> String: return "packages"
func get_aliases() -> Array: return ["apt-get"]
func get_summary() -> String: return "install, remove and search software packages"
func get_usage() -> String: return "apt [search|show|list|install|remove] [PKG...]"
func get_manual() -> String:
	return """apt manages the software installed on the system.
  apt search TERM     find packages by name or description
  apt show PKG        details about one package
  apt list --installed   everything currently installed
  apt install PKG     install it (and its dependencies)   (needs root)
  apt remove PKG      uninstall it                          (needs root)
  apt update          refresh the list of available packages (needs root)
Installing or removing software changes the whole machine, so it needs
privilege — prefix those with sudo."""


func execute(ctx: CommandContext) -> int:
	var operands: Array = []
	for a in ctx.args():
		if not str(a).begins_with("-"):
			operands.append(str(a))
	if operands.is_empty():
		return usage_error(ctx, "no command given")
	var sub: String = operands[0]
	var names: Array = operands.slice(1)
	match sub:
		"search":
			return _search(ctx, names)
		"show":
			return _show(ctx, names)
		"list":
			return _list(ctx, ctx.args())
		"policy":
			return _show(ctx, names)
		"update":
			return _update(ctx)
		"install", "reinstall":
			return _install(ctx, names)
		"remove", "purge", "autoremove":
			return _remove(ctx, names, sub == "purge")
		_:
			ctx.err("E: Invalid operation %s\n" % sub)
			return 100


func _need_root(ctx: CommandContext, verb: String) -> bool:
	if ctx.session.user == "root":
		return true
	ctx.err("E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)\n")
	ctx.err("E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), are you root?\n")
	ctx.out("Try: sudo apt %s ...\n" % verb, "dim")
	return false


func _search(ctx: CommandContext, terms: Array) -> int:
	if terms.is_empty():
		return usage_error(ctx, "search needs a term")
	var term := str(terms[0]).to_lower()
	var pkgs := ctx.machine().packages
	var names := pkgs.keys()
	names.sort()
	var hits := 0
	for name in names:
		var p: Dictionary = pkgs[name]
		if not (name.to_lower().contains(term) or str(p.description).to_lower().contains(term)):
			continue
		var tag := "/now" if bool(p.installed) else "/stable"
		ctx.out("%s%s %s %s" % [name, tag, p.version, p.section], "exec")
		ctx.out("  [installed]\n" if bool(p.installed) else "\n", "dim")
		ctx.out("  %s\n" % p.description)
		hits += 1
	if hits == 0:
		ctx.out("(no packages match \"%s\")\n" % term, "dim")
	return 0


func _show(ctx: CommandContext, names: Array) -> int:
	if names.is_empty():
		return usage_error(ctx, "show needs a package name")
	var pkgs := ctx.machine().packages
	for name in names:
		if not pkgs.has(name):
			ctx.err("N: Unable to locate package %s\n" % name)
			return 100
		var p: Dictionary = pkgs[name]
		ctx.out("Package: %s\n" % name, "header")
		ctx.out("Version: %s\n" % p.version)
		ctx.out("Section: %s\n" % p.section)
		ctx.out("Installed: %s\n" % ("yes" if bool(p.installed) else "no"))
		if not (p.depends as Array).is_empty():
			ctx.out("Depends: %s\n" % ", ".join(PackedStringArray(p.depends)))
		ctx.out("Description: %s\n" % p.description)
	return 0


func _list(ctx: CommandContext, args: Array) -> int:
	var only_installed := false
	for a in args:
		if str(a) == "--installed":
			only_installed = true
	var pkgs := ctx.machine().packages
	var names := pkgs.keys()
	names.sort()
	ctx.out("Listing...\n", "dim")
	for name in names:
		var p: Dictionary = pkgs[name]
		if only_installed and not bool(p.installed):
			continue
		var suffix := " [installed]" if bool(p.installed) else ""
		ctx.out("%s/%s %s\n" % [name, ("now" if bool(p.installed) else "stable"), p.version], "exec")
		if suffix != "":
			pass
	return 0


func _update(ctx: CommandContext) -> int:
	if not _need_root(ctx, "update"):
		return 100
	ctx.out("Hit:1 http://deb.sudoos.example stable InRelease\n", "dim")
	ctx.out("Reading package lists... Done\n")
	ctx.out("All packages are up to date.\n")
	return 0


func _install(ctx: CommandContext, names: Array) -> int:
	if names.is_empty():
		return usage_error(ctx, "install needs a package name")
	if not _need_root(ctx, "install"):
		return 100
	var pkgs := ctx.machine().packages
	# Resolve the full set to install: the requested packages + missing deps.
	var to_install: Array = []
	var seen := {}
	var queue: Array = names.duplicate()
	while not queue.is_empty():
		var name: String = str(queue.pop_front())
		if seen.has(name):
			continue
		seen[name] = true
		if not pkgs.has(name):
			ctx.err("E: Unable to locate package %s\n" % name)
			return 100
		if bool(pkgs[name].installed):
			continue
		to_install.append(name)
		for dep in pkgs[name].get("depends", []):
			queue.append(dep)
	ctx.out("Reading package lists... Done\n", "dim")
	ctx.out("Building dependency tree... Done\n", "dim")
	if to_install.is_empty():
		for name in names:
			ctx.out("%s is already the newest version (%s).\n" % [name, pkgs[name].version])
		ctx.out("0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.\n")
		return 0
	to_install.reverse() # dependencies first
	ctx.out("The following NEW packages will be installed:\n")
	ctx.out("  %s\n" % " ".join(PackedStringArray(to_install)))
	ctx.out("0 upgraded, %d newly installed, 0 to remove and 0 not upgraded.\n" % to_install.size())
	for name in to_install:
		pkgs[name].installed = true
		ctx.machine().vfs.put_file("/usr/share/doc/%s/copyright" % name, "%s\n" % name, "root", "root", Permissions.from_octal("644"))
		ctx.out("Setting up %s (%s) ...\n" % [name, pkgs[name].version])
		ctx.emit("package_installed", {"package": name})
	return 0


func _remove(ctx: CommandContext, names: Array, purge: bool) -> int:
	if names.is_empty():
		return usage_error(ctx, "remove needs a package name")
	if not _need_root(ctx, "remove"):
		return 100
	var pkgs := ctx.machine().packages
	var verb := "Purging" if purge else "Removing"
	var removed := 0
	for name in names:
		if not pkgs.has(name) or not bool(pkgs[name].installed):
			ctx.out("Package '%s' is not installed, so not removed\n" % name)
			continue
		pkgs[name].installed = false
		ctx.out("%s %s (%s) ...\n" % [verb, name, pkgs[name].version])
		ctx.emit("package_removed", {"package": name})
		removed += 1
	if removed > 0:
		ctx.out("0 upgraded, 0 newly installed, %d to remove and 0 not upgraded.\n" % removed)
	return 0
