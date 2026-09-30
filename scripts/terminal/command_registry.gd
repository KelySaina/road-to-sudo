class_name CommandRegistry
extends RefCounted
## Name -> BaseCommand instance. Commands are discovered from a directory so
## adding one never requires touching this file.

const COMMANDS_DIR := "res://scripts/commands/"

var _commands: Dictionary = {}
var _primary_names: Array = []


static func create_default() -> CommandRegistry:
	var r := CommandRegistry.new()
	r.discover(COMMANDS_DIR)
	return r


func discover(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Command directory not found: %s" % dir_path)
		return
	var files := Array(dir.get_files())
	files.sort()
	for f in files:
		var file_name: String = f.trim_suffix(".remap")
		if not (file_name.ends_with(".gd") or file_name.ends_with(".gdc")):
			continue
		if file_name.begins_with("base_command"):
			continue
		var script: Script = load(dir_path.path_join(file_name.trim_suffix("c") if file_name.ends_with(".gdc") else file_name))
		if script == null or not script.can_instantiate():
			continue
		var instance: Variant = script.new()
		if instance is BaseCommand:
			register(instance)


func register(cmd: BaseCommand) -> void:
	var cmd_name := cmd.get_command_name()
	if cmd_name == "":
		return
	if not _primary_names.has(cmd_name):
		_primary_names.append(cmd_name)
		_primary_names.sort()
	_commands[cmd_name] = cmd
	for alias in cmd.get_aliases():
		_commands[alias] = cmd


func has(cmd_name: String) -> bool:
	return _commands.has(cmd_name)


func get_command(cmd_name: String) -> BaseCommand:
	return _commands.get(cmd_name, null)


## Primary names only (no aliases), sorted.
func primary_names() -> Array:
	return _primary_names.duplicate()


## Every invocable name including aliases, sorted.
func all_names() -> Array:
	var names := _commands.keys()
	names.sort()
	return names


## "Did you mean" candidates: closest edit distance first, then the longest
## shared prefix (lss -> ls before less). Only the best distance tier is kept.
func suggest(typo: String, max_distance: int = 2) -> Array:
	var lowered := typo.to_lower()
	var scored: Array = []
	for n in all_names():
		# A one-letter command (l, alias for look) is a poor suggestion for a
		# longer typo — it "matches" almost everything by edit distance.
		if n.length() == 1 and lowered.length() > 1:
			continue
		var d := StringTools.edit_distance(lowered, n)
		if d <= max_distance:
			scored.append([d, -StringTools.shared_prefix_length(lowered, n), n])
	if scored.is_empty():
		return []
	scored.sort()
	var best: int = scored[0][0]
	var out: Array = []
	for s in scored:
		if s[0] == best and out.size() < 3:
			out.append(s[2])
	return out
