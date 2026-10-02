extends "res://tests/test_base.gd"
## Guards the translation layer. The dangerous failure mode is a translated
## string whose %-placeholders don't match the English it replaces: GDScript's
## `%` operator then crashes at the exact moment that line is shown, which a
## normal playthrough won't reach. So every locale is checked up front.


func test_fallback_passes_unknown_through() -> void:
	I18n.set_locale("en")
	check_eq(I18n.t("anything at all"), "anything at all", "en is identity")
	I18n.set_locale("fr")
	check_eq(I18n.t("zzz not a real game string zzz"), "zzz not a real game string zzz",
		"an untranslated string falls back to English, not a blank")
	I18n.set_locale("en")


func test_translation_is_applied() -> void:
	I18n.set_locale("fr")
	check(I18n.t("Continue") != "Continue", "a known UI string is translated")
	# Machine output must never be swept up by the content walker.
	var challenge := {"objective": "Continue", "setup": {"files": {"~/x": {"content": "Continue"}}}}
	var out: Variant = I18n.translate_content(challenge.duplicate(true))
	check(out.setup.files["~/x"].content == "Continue",
		"content under setup/ is left in English")
	I18n.set_locale("en")


## Every locale file: valid JSON, and each value carries exactly the
## placeholders of the English key it answers to, in the same order.
func test_placeholder_parity() -> void:
	var spec := RegEx.create_from_string("%[0-9]*[sdfx%]")
	for code in I18n.LOCALES:
		if code == I18n.DEFAULT_LOCALE:
			continue
		var path := "res://data/i18n/%s.json" % code
		var map := JsonLoader.load_dict(path)
		check(not map.is_empty(), "%s loads and is non-empty" % code)
		for en in map:
			var want := _specs(spec, en)
			var got := _specs(spec, str(map[en]))
			check_eq(got, want, "%s: placeholders match for %s" % [code, en.left(40)])


func _specs(spec: RegEx, text: String) -> Array:
	var out: Array = []
	for m in spec.search_all(text):
		out.append(m.get_string())
	return out
