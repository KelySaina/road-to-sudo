class_name VFSNode
extends RefCounted
## One inode in the virtual filesystem. Nodes do not know their parent,
## which avoids reference cycles; paths are always resolved from the root.

enum Kind { FILE, DIR }

var name: String = ""
var kind: Kind = Kind.FILE
var content: String = ""
var children: Dictionary = {}
var owner: String = "root"
var group: String = "root"
var mode: int = 420 # 644
var mtime: String = "Jun  5 09:14"


static func make_dir(p_name: String, p_owner: String = "root", p_group: String = "root", p_mode: int = 493) -> VFSNode:
	var n := VFSNode.new()
	n.name = p_name
	n.kind = Kind.DIR
	n.owner = p_owner
	n.group = p_group
	n.mode = p_mode
	return n


static func make_file(p_name: String, p_content: String = "", p_owner: String = "root", p_group: String = "root", p_mode: int = 420) -> VFSNode:
	var n := VFSNode.new()
	n.name = p_name
	n.kind = Kind.FILE
	n.content = p_content
	n.owner = p_owner
	n.group = p_group
	n.mode = p_mode
	return n


func is_dir() -> bool:
	return kind == Kind.DIR


func is_hidden() -> bool:
	return name.begins_with(".")


func size() -> int:
	return 4096 if is_dir() else content.to_utf8_buffer().size()


func kind_char() -> String:
	return "d" if is_dir() else "-"


func sorted_child_names() -> Array:
	var names := children.keys()
	names.sort_custom(func(a, b): return a.to_lower().trim_prefix(".") < b.to_lower().trim_prefix("."))
	return names


func deep_copy(new_name: String = "") -> VFSNode:
	var n := VFSNode.new()
	n.name = new_name if new_name != "" else name
	n.kind = kind
	n.content = content
	n.owner = owner
	n.group = group
	n.mode = mode
	n.mtime = mtime
	for child_name in children:
		n.children[child_name] = children[child_name].deep_copy()
	return n


func to_dict() -> Dictionary:
	var d := {"k": "d" if is_dir() else "f", "o": owner, "g": group, "m": mode, "t": mtime}
	if is_dir():
		var c := {}
		for child_name in children:
			c[child_name] = children[child_name].to_dict()
		d["c"] = c
	else:
		d["x"] = content
	return d


static func from_dict(p_name: String, d: Dictionary) -> VFSNode:
	var n := VFSNode.new()
	n.name = p_name
	n.kind = Kind.DIR if d.get("k", "f") == "d" else Kind.FILE
	n.owner = d.get("o", "root")
	n.group = d.get("g", "root")
	n.mode = int(d.get("m", 420))
	n.mtime = d.get("t", n.mtime)
	n.content = d.get("x", "")
	var c: Dictionary = d.get("c", {})
	for child_name in c:
		n.children[child_name] = VFSNode.from_dict(child_name, c[child_name])
	return n
