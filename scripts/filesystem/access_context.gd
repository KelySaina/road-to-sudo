class_name AccessContext
extends RefCounted
## "Who is asking?" — the identity used for every permission check.

var user: String = "nobody"
var groups: PackedStringArray = PackedStringArray()


func _init(p_user: String = "nobody", p_groups: PackedStringArray = PackedStringArray()) -> void:
	user = p_user
	groups = p_groups


func is_root() -> bool:
	return user == "root"


func in_group(group: String) -> bool:
	return groups.has(group)
