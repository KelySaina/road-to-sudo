class_name GitModel
extends RefCounted
## A small, honest model of a git repository living inside the VFS.
## The index (staging area) and commits are stored on `machine.git`, keyed by
## the working-tree root. Working-tree state is read live from the VFS and
## compared by content hash — so `git status` reflects real edits, and the
## challenge checker sees the same truth the player does.


## Finds the repository whose root contains `abs_path` (walks upward, like git).
static func repo_root_for(m: Machine, abs_path: String) -> String:
	var path := PathUtils.normalize(abs_path)
	while path != "":
		if m.git.has(path):
			return path
		if path == "/":
			break
		path = PathUtils.dirname(path)
	return ""


static func get_repo(m: Machine, root: String) -> Dictionary:
	return m.git.get(root, {})


static func init(m: Machine, vfs: VirtualFileSystem, root: String) -> bool:
	if m.git.has(root):
		return false
	m.git[root] = {"branch": "main", "index": {}, "commits": []}
	vfs.ensure_dir(root + "/.git")
	vfs.put_file(root + "/.git/HEAD", "ref: refs/heads/main\n")
	return true


## Content identity. Short, deterministic hex — collisions are irrelevant at
## this scale, and it stays stable across a snapshot/restore of the machine.
static func blob_hash(content: String) -> String:
	return "%08x" % (content.hash() & 0xFFFFFFFF)


static func head_tree(repo: Dictionary) -> Dictionary:
	var commits: Array = repo.get("commits", [])
	return commits[-1].tree.duplicate() if not commits.is_empty() else {}


static func head_hash(repo: Dictionary) -> String:
	var commits: Array = repo.get("commits", [])
	return str(commits[-1].hash) if not commits.is_empty() else ""


## Repo-relative paths of every file in the working tree (skips .git/).
static func working_files(vfs: VirtualFileSystem, root: String) -> Dictionary:
	var out := {}
	var node := vfs.get_node_at(root)
	if node != null:
		_walk(node, "", out)
	return out


static func _walk(node: VFSNode, prefix: String, out: Dictionary) -> void:
	for name in node.children:
		var child: VFSNode = node.children[name]
		if child.is_dir():
			if name == ".git":
				continue
			_walk(child, prefix + name + "/", out)
		else:
			out[prefix + name] = blob_hash(child.content)


static func is_ignored(vfs: VirtualFileSystem, root: String, rel: String) -> bool:
	var node := vfs.get_node_at(root + "/.gitignore")
	if node == null or node.is_dir():
		return false
	for raw in node.content.split("\n"):
		var pat := raw.strip_edges()
		if pat == "" or pat.begins_with("#"):
			continue
		var dir_only := pat.ends_with("/")
		pat = pat.trim_suffix("/")
		if pat == rel or PathUtils.basename(rel) == pat:
			return true
		if rel.begins_with(pat + "/") or ("/" + rel).ends_with("/" + pat + "/") or rel.begins_with(pat):
			if dir_only or rel.begins_with(pat + "/"):
				return true
		if pat.contains("*") and (rel.match(pat) or PathUtils.basename(rel).match(pat)):
			return true
	return false


## The full working state, split the way `git status` presents it.
static func status(m: Machine, vfs: VirtualFileSystem, root: String) -> Dictionary:
	var repo := get_repo(m, root)
	var index: Dictionary = repo.get("index", {})
	var head := head_tree(repo)
	var working := working_files(vfs, root)

	var staged: Array = []      # index differs from HEAD (to be committed)
	var modified: Array = []    # tracked file changed but not staged
	var deleted: Array = []     # tracked file removed from the working tree
	var untracked: Array = []

	var index_keys := {}
	for k in index:
		index_keys[k] = true
	for k in head:
		index_keys[k] = true
	for path in index_keys:
		if index.get(path, null) != head.get(path, null):
			if not index.has(path):
				staged.append({"path": path, "kind": "deleted"})
			elif not head.has(path):
				staged.append({"path": path, "kind": "new file"})
			else:
				staged.append({"path": path, "kind": "modified"})

	for path in index:
		if not working.has(path):
			deleted.append(path)
		elif working[path] != index[path]:
			modified.append(path)
	for path in working:
		if not index.has(path) and not is_ignored(vfs, root, path):
			untracked.append(path)

	staged.sort_custom(func(a, b): return a.path < b.path)
	modified.sort()
	deleted.sort()
	untracked.sort()
	return {
		"branch": repo.get("branch", "main"),
		"staged": staged, "modified": modified, "deleted": deleted, "untracked": untracked,
		"has_commits": not repo.get("commits", []).is_empty(),
	}


static func is_clean(st: Dictionary) -> bool:
	return st.staged.is_empty() and st.modified.is_empty() and st.deleted.is_empty() and st.untracked.is_empty()


## Stages paths. "." (or the root) stages everything; a directory stages its
## subtree; a file stages that file (or records its deletion).
static func add(m: Machine, vfs: VirtualFileSystem, root: String, cwd: String, specs: Array) -> Array:
	var repo := get_repo(m, root)
	var index: Dictionary = repo.index
	var working := working_files(vfs, root)
	var errors: Array = []
	for spec in specs:
		var abs_spec := PathUtils.normalize(PathUtils.join(cwd, str(spec)))
		var rel_base := "" if abs_spec == root else abs_spec.substr(root.length() + 1)
		var matched := false
		if str(spec) == "." or abs_spec == root:
			rel_base = ""
		# Stage every working file under rel_base (unless ignored).
		for path in working:
			if rel_base == "" or path == rel_base or path.begins_with(rel_base + "/"):
				if not is_ignored(vfs, root, path):
					index[path] = working[path]
					matched = true
		# A tracked file that no longer exists: `git add` records the deletion.
		for path in index.keys():
			if not working.has(path) and (rel_base == "" or path == rel_base or path.begins_with(rel_base + "/")):
				index.erase(path)
				matched = true
		if not matched and rel_base != "":
			errors.append(str(spec))
	return errors


static func commit(m: Machine, vfs: VirtualFileSystem, root: String, message: String, author: String) -> Dictionary:
	var repo := get_repo(m, root)
	var index: Dictionary = repo.index
	if index.hash() == head_tree(repo).hash() and not (repo.commits as Array).is_empty():
		return {}
	if index.is_empty() and (repo.commits as Array).is_empty():
		return {}
	var tree := index.duplicate()
	var parent := head_hash(repo)
	var h := blob_hash(message + parent + str(tree) + str(Time.get_ticks_usec()))
	var files_changed := 0
	var head := head_tree(repo)
	for k in tree:
		if head.get(k, null) != tree[k]:
			files_changed += 1
	for k in head:
		if not tree.has(k):
			files_changed += 1
	var commit := {"hash": h, "message": message, "author": author, "tree": tree, "parent": parent, "files": files_changed}
	repo.commits.append(commit)
	return commit
