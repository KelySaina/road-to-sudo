class_name I18n
extends RefCounted
## Translation, keyed by the English source string.
##
## There is no key scheme to invent and no catalogue to keep in sync: the code
## and the data keep their English text, and `data/i18n/<locale>.json` maps that
## English to the target language. A string with no entry falls back to English,
## so a half-finished translation degrades into a readable game rather than into
## blank labels or raw keys.
##
## WHAT IS NEVER TRANSLATED: anything the simulated machine prints. `ls -l`
## columns, "Permission denied", "No such file or directory", prompts, file
## contents, and every command in a solution or an example stay in English,
## because that is the Linux the game is teaching. Only the layer that teaches
## around it — UI, objectives, hints, narration, help text — is localised.

const DIR := "res://data/i18n/"
const DEFAULT_LOCALE := "en"
## Locale code -> the name shown in Settings, in that language.
const LOCALES := {"en": "English", "fr": "Français"}

static var _locale := DEFAULT_LOCALE
static var _map: Dictionary = {}

# Keys whose values are prose meant for the player. Anything not named here is
# left alone, which is the safe default for a data file full of shell commands.
const TRANSLATABLE := [
	"title", "subtitle", "description", "objective", "expert_objective",
	"briefing", "expert_briefing", "tips", "hints", "explanation",
	"say", "intro", "outro", "learned", "name", "teaches", "label", "blurb", "desc",
]
# Subtrees that configure the machine or match conditions. Translating a word in
# here would change what the game checks, not what it says.
const NEVER := ["setup", "success", "when", "params", "respawn", "solution",
	"unlocks", "reactions_from", "files", "processes"]


static func locale() -> String:
	return _locale


static func set_locale(code: String) -> void:
	_locale = code if LOCALES.has(code) else DEFAULT_LOCALE
	_map = {} if _locale == DEFAULT_LOCALE else JsonLoader.load_dict(DIR + _locale + ".json")


## Translate one string. Unknown text comes back unchanged.
static func t(text: String) -> String:
	if _map.is_empty():
		return text
	return _map.get(text, text)


## Translate a value that may be a string or an array of strings (the shape
## `hints`, `briefing` and `intro` all use).
static func t_any(value: Variant) -> Variant:
	if value is String:
		return t(value)
	if value is Array:
		var out: Array = []
		for v in value:
			out.append(t_any(v))
		return out
	return value


## Walk a loaded content dictionary and translate the prose in it in place.
## Called from JsonLoader, so every consumer — challenges, levels, the adventure
## worlds, achievements — gets a localised copy without knowing i18n exists.
static func translate_content(value: Variant) -> Variant:
	if _map.is_empty():
		return value
	if value is Array:
		for i in value.size():
			value[i] = translate_content(value[i])
		return value
	if not (value is Dictionary):
		return value
	var d: Dictionary = value
	for key in d.keys():
		if NEVER.has(key):
			continue
		var v: Variant = d[key]
		if TRANSLATABLE.has(key):
			# `teaches` is a sentence on an adventure orb but a list of command
			# names on a challenge; only the prose form is ours to touch.
			if key == "teaches" and not (v is String):
				continue
			d[key] = t_any(v)
		elif v is Dictionary or v is Array:
			d[key] = translate_content(v)
	return d


## Every English string the translation file currently carries, for coverage
## checks in tests and for the extraction tool.
static func known_keys() -> Array:
	return _map.keys()
