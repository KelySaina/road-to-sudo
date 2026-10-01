extends Node
## Lightweight localization. Translations are keyed by the ENGLISH string, so a
## call site reads `Loc.t("Start Journey")` and any string without a French
## entry simply falls back to English — i18n can be filled in incrementally
## without ever breaking. Linux commands and their output stay English (as a
## real terminal is); only the game's own texts and explanations translate.

signal locale_changed(locale: String)

const FR_PATH := "res://data/i18n/fr.json"

var locale := "en"
var _fr: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_fr = JsonLoader.load_dict(FR_PATH)


func set_locale(new_locale: String) -> void:
	new_locale = "fr" if new_locale == "fr" else "en"
	if new_locale == locale:
		return
	locale = new_locale
	locale_changed.emit(locale)


## Translate one string (English → French when in fr mode, else unchanged).
func t(s: String) -> String:
	if locale == "fr" and _fr.has(s):
		return str(_fr[s])
	return s


## Translate each line of an array (briefings, hints, …).
func tlines(lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		out.append(t(str(line)))
	return out
