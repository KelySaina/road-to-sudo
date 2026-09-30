extends Node
## Local save file (autoload "SaveManager"). JSON in user://, written
## atomically (temp file + rename) so a crash never corrupts progress.

const SAVE_PATH := "user://road_to_sudo_save.json"

## Overridable (tests point it elsewhere so they never touch a real save).
var save_path: String = SAVE_PATH
var _cache: Dictionary = {}


func has_save() -> bool:
	return FileAccess.file_exists(save_path) and load_profile().started


func load_profile() -> PlayerProfile:
	return PlayerProfile.from_dict(_read().get("profile", {}))


## World = the campaign machine + shell state, so Continue resumes exactly.
func load_world(slot: String) -> Dictionary:
	return _read().get("worlds", {}).get(slot, {})


func save(profile: PlayerProfile, worlds: Dictionary = {}) -> bool:
	var data := _read().duplicate()
	data["profile"] = profile.to_dict()
	var all_worlds: Dictionary = data.get("worlds", {})
	for slot in worlds:
		all_worlds[slot] = worlds[slot]
	data["worlds"] = all_worlds
	data["saved_at"] = int(Time.get_unix_time_from_system())
	var tmp_path := save_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(save_path))
	if err != OK:
		push_error("Cannot finalize save: %s" % error_string(err))
		return false
	_cache = data
	return true


func clear_world(slot: String) -> void:
	var data := _read().duplicate()
	var worlds: Dictionary = data.get("worlds", {})
	worlds.erase(slot)
	data["worlds"] = worlds
	_cache = data


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_cache = {}


func _read() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if FileAccess.file_exists(save_path):
		_cache = JsonLoader.load_dict(save_path)
	return _cache
