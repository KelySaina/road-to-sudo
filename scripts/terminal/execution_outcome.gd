class_name ExecutionOutcome
extends RefCounted
## What one submitted line produced. The UI renders `chunks`; gameplay
## systems read `events` (permission errors, deletions, sudo attempts...).

var chunks: Array = [] # {"stream": "out" | "err" | "sys", "text": String, "style": String}
var exit_code: int = 0
var clear_screen: bool = false
var events: Array = [] # {"name": String, "data": Dictionary}
var records: Array = [] # command_log entries produced by this line
var line: String = ""


func write(stream: String, text: String, style: String = "") -> void:
	if text == "":
		return
	chunks.append({"stream": stream, "text": text, "style": style})


func emit(event_name: String, data: Dictionary = {}) -> void:
	events.append({"name": event_name, "data": data})


func has_event(event_name: String) -> bool:
	for e in events:
		if e.name == event_name:
			return true
	return false


func stdout_text() -> String:
	var out := ""
	for c in chunks:
		if c.stream == "out":
			out += c.text
	return out


func all_text() -> String:
	var out := ""
	for c in chunks:
		out += c.text
	return out
