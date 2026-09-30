class_name JsonLoader
extends RefCounted
## Small wrapper around FileAccess + JSON with readable error reporting.


static func load_dict(path: String) -> Dictionary:
	var value: Variant = load_any(path)
	return value if value is Dictionary else {}


static func load_array(path: String) -> Array:
	var value: Variant = load_any(path)
	return value if value is Array else []


static func load_any(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func list_json_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		# Exported builds may list "x.json.remap"-style entries; normalize.
		var name := f.trim_suffix(".remap")
		if name.ends_with(".json"):
			out.append(dir_path.path_join(name))
	out.sort()
	return out
