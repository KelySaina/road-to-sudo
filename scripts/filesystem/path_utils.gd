class_name PathUtils
extends RefCounted
## Pure string helpers for POSIX-style paths. No filesystem access here.


static func is_absolute(path: String) -> bool:
	return path.begins_with("/")


## Collapses ".", "..", duplicate slashes. Always returns an absolute path
## when given one. "/.." stays "/", like the real kernel.
static func normalize(path: String) -> String:
	var absolute := is_absolute(path)
	var parts: Array = []
	for part in path.split("/", false):
		if part == ".":
			continue
		if part == "..":
			if parts.size() > 0 and parts[-1] != "..":
				parts.pop_back()
			elif not absolute:
				parts.append("..")
			continue
		parts.append(part)
	var joined := "/".join(PackedStringArray(parts))
	if absolute:
		return "/" + joined
	return joined if joined != "" else "."


static func join(base: String, rel: String) -> String:
	if rel == "":
		return normalize(base)
	if is_absolute(rel):
		return normalize(rel)
	return normalize(base.trim_suffix("/") + "/" + rel)


static func basename(path: String) -> String:
	var p := path.trim_suffix("/") if path != "/" else path
	if p == "/":
		return "/"
	var idx := p.rfind("/")
	return p if idx == -1 else p.substr(idx + 1)


static func dirname(path: String) -> String:
	var p := path.trim_suffix("/") if path != "/" else path
	var idx := p.rfind("/")
	if idx == -1:
		return "."
	if idx == 0:
		return "/"
	return p.substr(0, idx)


## Replaces a leading home directory with "~" for prompts.
static func prettify(path: String, home: String) -> String:
	if home != "" and home != "/" and (path == home or path.begins_with(home + "/")):
		return "~" + path.substr(home.length())
	return path


static func depth(path: String) -> int:
	return path.split("/", false).size()
