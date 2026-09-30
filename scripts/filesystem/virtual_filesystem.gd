class_name VirtualFileSystem
extends RefCounted
## In-memory POSIX-like filesystem. Every public operation that takes an
## AccessContext enforces permissions; pass null for "kernel" access
## (world building, save/load, challenge setup).

const ENOENT := "No such file or directory"
const EACCES := "Permission denied"
const ENOTDIR := "Not a directory"
const EISDIR := "Is a directory"
const EEXIST := "File exists"
const ENOTEMPTY := "Directory not empty"
const EINVAL := "Invalid argument"

const DEFAULT_FILE_MODE := 420 # 644
const DEFAULT_DIR_MODE := 493 # 755

var root: VFSNode = VFSNode.make_dir("/")


# --- lookup -----------------------------------------------------------------

func get_node_at(abs_path: String) -> VFSNode:
	var node := root
	for part in PathUtils.normalize(abs_path).split("/", false):
		if not node.is_dir() or not node.children.has(part):
			return null
		node = node.children[part]
	return node


func exists(abs_path: String) -> bool:
	return get_node_at(abs_path) != null


func is_dir(abs_path: String) -> bool:
	var n := get_node_at(abs_path)
	return n != null and n.is_dir()


## Walks the path checking search (x) permission on every directory crossed.
func lookup(abs_path: String, access: AccessContext = null) -> VfsResult:
	var node := root
	var parts := PathUtils.normalize(abs_path).split("/", false)
	for i in parts.size():
		if not node.is_dir():
			return VfsResult.fail(ENOTDIR)
		if access != null and not Permissions.can(node, access, Permissions.EXEC):
			return VfsResult.fail(EACCES)
		if not node.children.has(parts[i]):
			return VfsResult.fail(ENOENT)
		node = node.children[parts[i]]
	return VfsResult.success(node)


func _parent_for_create(abs_path: String, access: AccessContext) -> VfsResult:
	var parent_res := lookup(PathUtils.dirname(abs_path), access)
	if not parent_res.ok:
		return parent_res
	if not parent_res.node.is_dir():
		return VfsResult.fail(ENOTDIR)
	if access != null and not Permissions.can(parent_res.node, access, Permissions.WRITE | Permissions.EXEC):
		return VfsResult.fail(EACCES)
	return parent_res


# --- reading ----------------------------------------------------------------

func read_file(abs_path: String, access: AccessContext = null) -> VfsResult:
	var res := lookup(abs_path, access)
	if not res.ok:
		return res
	if res.node.is_dir():
		return VfsResult.fail(EISDIR)
	if access != null and not Permissions.can(res.node, access, Permissions.READ):
		return VfsResult.fail(EACCES)
	return VfsResult.success(res.node, res.node.content)


func list_dir(abs_path: String, access: AccessContext = null) -> VfsResult:
	var res := lookup(abs_path, access)
	if not res.ok:
		return res
	if not res.node.is_dir():
		return VfsResult.success(res.node, [PathUtils.basename(abs_path)])
	if access != null and not Permissions.can(res.node, access, Permissions.READ):
		return VfsResult.fail(EACCES)
	return VfsResult.success(res.node, res.node.sorted_child_names())


## Every path under (and including) abs_path, depth-first, sorted.
## Directories the accessor cannot read are skipped and reported in `value`.
func walk(abs_path: String, access: AccessContext = null) -> Dictionary:
	var paths: Array = []
	var denied: Array = []
	var start := get_node_at(abs_path)
	if start != null:
		_walk_into(PathUtils.normalize(abs_path), start, access, paths, denied)
	return {"paths": paths, "denied": denied}


func _walk_into(path: String, node: VFSNode, access: AccessContext, paths: Array, denied: Array) -> void:
	paths.append(path)
	if not node.is_dir():
		return
	if access != null and not Permissions.can(node, access, Permissions.READ | Permissions.EXEC):
		denied.append(path)
		return
	for child_name in node.sorted_child_names():
		var child_path: String = path.trim_suffix("/") + "/" + child_name
		_walk_into(child_path, node.children[child_name], access, paths, denied)


# --- writing ----------------------------------------------------------------

func write_file(abs_path: String, content: String, access: AccessContext = null, append: bool = false) -> VfsResult:
	var existing := lookup(abs_path, access)
	if existing.ok:
		if existing.node.is_dir():
			return VfsResult.fail(EISDIR)
		if access != null and not Permissions.can(existing.node, access, Permissions.WRITE):
			return VfsResult.fail(EACCES)
		existing.node.content = existing.node.content + content if append else content
		existing.node.mtime = _now()
		return VfsResult.success(existing.node)
	if existing.error != ENOENT:
		return existing
	var parent_res := _parent_for_create(abs_path, access)
	if not parent_res.ok:
		return parent_res
	var node := VFSNode.make_file(PathUtils.basename(abs_path), content, _owner_of(access), _group_of(access), DEFAULT_FILE_MODE)
	node.mtime = _now()
	parent_res.node.children[node.name] = node
	return VfsResult.success(node)


func touch(abs_path: String, access: AccessContext = null, mode: int = -1) -> VfsResult:
	var existing := lookup(abs_path, access)
	if existing.ok:
		if access != null and not existing.node.is_dir() and not Permissions.can(existing.node, access, Permissions.WRITE):
			return VfsResult.fail(EACCES)
		existing.node.mtime = _now()
		return existing
	var res := write_file(abs_path, "", access)
	if res.ok and mode >= 0:
		res.node.mode = mode
	return res


func make_dir(abs_path: String, access: AccessContext = null, parents: bool = false, mode: int = -1) -> VfsResult:
	var normalized := PathUtils.normalize(abs_path)
	var existing := get_node_at(normalized)
	if existing != null:
		if parents and existing.is_dir():
			return VfsResult.success(existing)
		return VfsResult.fail(EEXIST)
	if parents and not exists(PathUtils.dirname(normalized)):
		var up := make_dir(PathUtils.dirname(normalized), access, true)
		if not up.ok:
			return up
	var parent_res := _parent_for_create(normalized, access)
	if not parent_res.ok:
		return parent_res
	var node := VFSNode.make_dir(PathUtils.basename(normalized), _owner_of(access), _group_of(access), mode if mode >= 0 else DEFAULT_DIR_MODE)
	node.mtime = _now()
	parent_res.node.children[node.name] = node
	return VfsResult.success(node)


func remove(abs_path: String, access: AccessContext = null, recursive: bool = false, dirs_only_if_empty: bool = false) -> VfsResult:
	var normalized := PathUtils.normalize(abs_path)
	if normalized == "/":
		return VfsResult.fail("Refusing to remove '/' (nice try)")
	var res := lookup(normalized, access)
	if not res.ok:
		return res
	if res.node.is_dir():
		if dirs_only_if_empty and not res.node.children.is_empty():
			return VfsResult.fail(ENOTEMPTY)
		if not recursive and not dirs_only_if_empty:
			return VfsResult.fail(EISDIR)
	var parent_res := _parent_for_create(normalized, access)
	if not parent_res.ok:
		return parent_res
	parent_res.node.children.erase(res.node.name)
	return VfsResult.success(res.node)


func copy(src: String, dst: String, access: AccessContext = null, recursive: bool = false) -> VfsResult:
	var src_res := lookup(src, access)
	if not src_res.ok:
		return src_res
	if src_res.node.is_dir() and not recursive:
		return VfsResult.fail("-r not specified; omitting directory")
	if access != null and not Permissions.can(src_res.node, access, Permissions.READ):
		return VfsResult.fail(EACCES)
	var target := _final_target(src, dst)
	if target == PathUtils.normalize(src) or target.begins_with(PathUtils.normalize(src) + "/"):
		return VfsResult.fail("cannot copy a directory into itself")
	var dst_node := get_node_at(target)
	if dst_node != null and dst_node.is_dir() != src_res.node.is_dir():
		return VfsResult.fail(EISDIR if dst_node.is_dir() else ENOTDIR)
	var parent_res := _parent_for_create(target, access)
	if not parent_res.ok:
		return parent_res
	var clone := src_res.node.deep_copy(PathUtils.basename(target))
	if access != null:
		_reown(clone, _owner_of(access), _group_of(access))
	clone.mtime = _now()
	parent_res.node.children[clone.name] = clone
	return VfsResult.success(clone)


func move(src: String, dst: String, access: AccessContext = null) -> VfsResult:
	var normalized_src := PathUtils.normalize(src)
	var src_res := lookup(normalized_src, access)
	if not src_res.ok:
		return src_res
	var target := _final_target(normalized_src, dst)
	if target == normalized_src:
		return VfsResult.success(src_res.node)
	if target.begins_with(normalized_src + "/"):
		return VfsResult.fail("cannot move a directory into itself")
	var src_parent := _parent_for_create(normalized_src, access)
	if not src_parent.ok:
		return src_parent
	var dst_parent := _parent_for_create(target, access)
	if not dst_parent.ok:
		return dst_parent
	var existing := get_node_at(target)
	if existing != null and existing.is_dir():
		return VfsResult.fail(EISDIR)
	src_parent.node.children.erase(src_res.node.name)
	src_res.node.name = PathUtils.basename(target)
	dst_parent.node.children[src_res.node.name] = src_res.node
	return VfsResult.success(src_res.node)


## cp/mv semantics: copying onto an existing directory puts the file inside it.
func _final_target(src: String, dst: String) -> String:
	var d := PathUtils.normalize(dst)
	if is_dir(d):
		return PathUtils.join(d, PathUtils.basename(src))
	return d


func _reown(node: VFSNode, p_owner: String, p_group: String) -> void:
	node.owner = p_owner
	node.group = p_group
	for child_name in node.children:
		_reown(node.children[child_name], p_owner, p_group)


# --- kernel-level helpers (no permission checks) ------------------------------

## Creates missing directories along the way, root-owned 755 by default.
func ensure_dir(abs_path: String, p_owner: String = "root", p_group: String = "root", p_mode: int = DEFAULT_DIR_MODE) -> VFSNode:
	var node := root
	for part in PathUtils.normalize(abs_path).split("/", false):
		if not node.children.has(part):
			node.children[part] = VFSNode.make_dir(part, p_owner, p_group, p_mode)
		node = node.children[part]
	return node


func put_file(abs_path: String, content: String, p_owner: String = "root", p_group: String = "root", p_mode: int = DEFAULT_FILE_MODE) -> VFSNode:
	var parent := ensure_dir(PathUtils.dirname(abs_path))
	var node := VFSNode.make_file(PathUtils.basename(abs_path), content, p_owner, p_group, p_mode)
	parent.children[node.name] = node
	return node


func _owner_of(access: AccessContext) -> String:
	return "root" if access == null else access.user


func _group_of(access: AccessContext) -> String:
	if access == null or access.groups.is_empty():
		return "root"
	return access.groups[0]


static func _now() -> String:
	var t := Time.get_datetime_dict_from_system()
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %2d %02d:%02d" % [months[int(t.month) - 1], int(t.day), int(t.hour), int(t.minute)]


func to_dict() -> Dictionary:
	return root.to_dict()


static func from_dict(d: Dictionary) -> VirtualFileSystem:
	var vfs := VirtualFileSystem.new()
	vfs.root = VFSNode.from_dict("/", d)
	return vfs
