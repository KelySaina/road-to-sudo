class_name VfsResult
extends RefCounted
## Return value for filesystem operations. `error` is a short errno-style
## message ("No such file or directory") that commands prefix with context.

var ok: bool = true
var error: String = ""
var node: VFSNode = null
var value: Variant = null


static func success(p_node: VFSNode = null, p_value: Variant = null) -> VfsResult:
	var r := VfsResult.new()
	r.node = p_node
	r.value = p_value
	return r


static func fail(message: String) -> VfsResult:
	var r := VfsResult.new()
	r.ok = false
	r.error = message
	return r
