extends Control
## Title screen. Emits intents; Main performs them.

signal journey_requested(difficulty: String, skip_basics: bool)
signal continue_requested()
signal practice_requested()
signal adventure_requested()
signal settings_changed()
signal language_changed()

const TAGLINES := [
	["whoami", "player"],
	["ls -la ~", ""],
	["grep -r ERROR /var/log | wc -l", "42"],
	["chmod +x deploy.sh && ./deploy.sh", "deployed."],
	["sudo -i", "root@server:~#"],
]
const SPEEDS := ["instant", "fast", "normal"]
const FONT_SIZES := [15, 17, 19, 21]

var _selected_difficulty := "beginner"
var _difficulty_buttons: Dictionary = {}
var _tag_index := 0
var _tag_time := 0.0
var _blink := 0.0

@onready var title: Label = %Title
@onready var tagline: Label = %Tagline
@onready var home: VBoxContainer = %Home
@onready var new_journey: VBoxContainer = %NewJourney
@onready var achievements_page: VBoxContainer = %Achievements
@onready var settings_page: VBoxContainer = %Settings
@onready var start_button: Button = %StartButton
@onready var continue_button: Button = %ContinueButton
@onready var practice_button: Button = %PracticeButton
@onready var difficulties: VBoxContainer = %Difficulties
@onready var skip_basics: CheckBox = %SkipBasics
@onready var warning: Label = %Warning
@onready var ach_heading: Label = %AchHeading
@onready var ach_list: VBoxContainer = %AchList
@onready var speed: OptionButton = %Speed
@onready var font_size: OptionButton = %FontSize
@onready var difficulty_option: OptionButton = %Difficulty
@onready var save_info: Label = %SaveInfo
@onready var reset_button: Button = %ResetButton
@onready var reset_confirm: HBoxContainer = %ResetConfirm


func _ready() -> void:
	start_button.pressed.connect(_open_new_journey)
	continue_button.pressed.connect(func(): continue_requested.emit())
	practice_button.pressed.connect(func(): practice_requested.emit())
	%AdventureButton.pressed.connect(func(): adventure_requested.emit())
	%AchievementsButton.pressed.connect(_open_achievements)
	%SettingsButton.pressed.connect(_open_settings)
	%ExitButton.pressed.connect(func(): get_tree().quit())
	%BackButton.pressed.connect(_show_home)
	%AchBack.pressed.connect(_show_home)
	%SetBack.pressed.connect(_show_home)
	%BeginButton.pressed.connect(_begin)
	reset_button.pressed.connect(func():
		reset_confirm.visible = true
		reset_button.visible = false
		%ResetNo.grab_focus())
	%ResetNo.pressed.connect(_cancel_reset)
	%ResetYes.pressed.connect(_do_reset)
	skip_basics.toggled.connect(func(_on): _update_warning())
	_localize_static()
	_build_difficulties()
	_build_settings()
	_build_language()
	_build_audio_toggles()
	_wire_button_sounds(self)
	_show_home()


## The menu's layout is authored in English in the .tscn; this re-applies each
## static label through I18n at load, so French (or any locale) shows without a
## second copy of the scene. English locale returns the same strings unchanged.
func _localize_static() -> void:
	var map := {
		"%StartButton": "Start Journey",
		"%ContinueButton": "Continue",
		"%PracticeButton": "Practice Lab",
		"%AdventureButton": "Adventure — The Ascent to Root",
		"%AchievementsButton": "Achievements",
		"%SettingsButton": "Settings",
		"%ExitButton": "Exit",
		"%BackButton": "← Back",
		"%BeginButton": "Begin  ⏎",
		"%AchBack": "← Back",
		"%SetBack": "← Back",
		"%ResetButton": "Reset all progress…",
		"%ResetNo": "Keep it",
		"%ResetYes": "Delete",
		"%AchHeading": "Achievements",
		"%SkipBasics": "I know the basics — skip to the first real problem",
	}
	for path in map:
		var n := get_node_or_null(NodePath(path))
		if n != null:
			n.text = I18n.t(map[path])
	# Headings and the footer, reached by path rather than unique name.
	_set_label("Top/Center/Column/Card/Pages/NewJourney/Heading", "How much do you already know?")
	_set_label("Top/Center/Column/Card/Pages/Settings/SetHeading", "Settings")
	_set_label("Top/Center/Column/Card/Pages/Settings/Grid/SpeedLabel", "Narration speed")
	_set_label("Top/Center/Column/Card/Pages/Settings/Grid/FontLabel", "Text size")
	_set_label("Top/Center/Column/Card/Pages/Settings/Grid/DiffLabel", "Difficulty (current journey)")
	_set_label("Top/Center/Column/Card/Pages/Settings/ResetConfirm/ResetQuestion", "rm -rf ~/progress ? This cannot be undone.")
	_set_label("Top/Center/Column/Footer", "v0.3.1 · ↑↓ navigate · Enter select · Esc back")


func _set_label(path: String, english: String) -> void:
	var n := get_node_or_null(NodePath(path))
	if n != null and n is Label:
		n.text = I18n.t(english)


## A language dropdown, added to the settings grid in code so the .tscn stays
## layout-only. Switching rebuilds the menu, which re-runs _localize_static.
func _build_language() -> void:
	var grid := speed.get_parent()
	var lang_label := Label.new()
	lang_label.text = I18n.t("Language")
	lang_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picker := OptionButton.new()
	var codes: Array = I18n.LOCALES.keys()
	for code in codes:
		picker.add_item(str(I18n.LOCALES[code]))
	picker.select(maxi(0, codes.find(I18n.locale())))
	picker.item_selected.connect(func(i):
		Game.set_locale(str(codes[i]))
		language_changed.emit())
	grid.add_child(lang_label)
	grid.add_child(picker)
	grid.move_child(lang_label, 0)
	grid.move_child(picker, 1)


## Give every button a navigate-on-focus and select-on-press sound. Done by
## walking the tree so new buttons are covered without extra wiring.
func _wire_button_sounds(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.focus_entered.connect(func(): Audio.play("navigate"))
			child.pressed.connect(func(): Audio.play("select"))
		_wire_button_sounds(child)


## Music and sound-effects toggles, added to the settings grid like the
## language picker. Each persists to the profile and re-applies immediately.
func _build_audio_toggles() -> void:
	var grid := speed.get_parent()
	for spec in [{"key": "music", "label": "Music"}, {"key": "sfx", "label": "Sound effects"}]:
		var lbl := Label.new()
		lbl.text = I18n.t(spec.label)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := CheckButton.new()
		box.button_pressed = bool(Game.profile.settings.get(spec.key, true))
		var key: String = spec.key
		box.toggled.connect(func(on):
			Game.profile.settings[key] = on
			Audio.apply_settings()
			Game.save_now())
		grid.add_child(lbl)
		grid.add_child(box)


func _process(delta: float) -> void:
	_blink += delta
	title.text = "ROAD TO SUDO" + ("_" if fmod(_blink, 1.0) < 0.55 else " ")
	_animate_tagline(delta)


func _animate_tagline(delta: float) -> void:
	_tag_time += delta
	var cmd: String = TAGLINES[_tag_index][0]
	var reply: String = TAGLINES[_tag_index][1]
	var typed := int(_tag_time * 16.0)
	if typed <= cmd.length():
		tagline.text = "$ " + cmd.substr(0, typed)
	elif _tag_time < cmd.length() / 16.0 + 2.2:
		tagline.text = "$ " + cmd + ("   →  " + reply if reply != "" else "")
	else:
		_tag_time = 0.0
		_tag_index = (_tag_index + 1) % TAGLINES.size()
	tagline.add_theme_color_override("font_color", UiTheme.ERROR if reply.begins_with("root") and typed > cmd.length() else UiTheme.DIM)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not home.visible:
		_show_home()
		get_viewport().set_input_as_handled()


# --- pages ---------------------------------------------------------------------

func _show_page(page: Control) -> void:
	for p in [home, new_journey, achievements_page, settings_page]:
		p.visible = p == page


func _show_home() -> void:
	_show_page(home)
	var has_save := SaveManager.has_save()
	continue_button.disabled = not has_save
	if has_save:
		var p := SaveManager.load_profile()
		var c := Game.library.get_challenge(p.current_challenge)
		var where := I18n.t(c.title) if c != null else I18n.t("journey complete")
		continue_button.text = I18n.t("Continue   ·  %s · %d XP · %s") % [I18n.t(str(Progression.new(p).current_rank().name)), p.xp, where]
	else:
		continue_button.text = I18n.t("Continue")
	(continue_button if has_save else start_button).grab_focus()


func _open_new_journey() -> void:
	_show_page(new_journey)
	_select_difficulty(_selected_difficulty)
	_update_warning()
	_difficulty_buttons[_selected_difficulty].grab_focus()


func _build_difficulties() -> void:
	var group := ButtonGroup.new()
	for d in DifficultySettings.all():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = d.label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = &"MenuButtonBig"
		var diff_id: String = d.id
		b.pressed.connect(func():
			if _selected_difficulty == diff_id and b.button_pressed and b.has_focus() and Input.is_action_just_pressed("ui_accept"):
				_begin()
			_select_difficulty(diff_id))
		var desc := Label.new()
		desc.text = d.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.theme_type_variation = &"DimLabel"
		box.add_child(b)
		box.add_child(desc)
		difficulties.add_child(box)
		_difficulty_buttons[diff_id] = b


func _select_difficulty(diff_id: String) -> void:
	_selected_difficulty = diff_id
	_difficulty_buttons[diff_id].button_pressed = true
	skip_basics.button_pressed = skip_basics.button_pressed and diff_id != "beginner"
	skip_basics.disabled = diff_id == "beginner"
	_update_warning()


func _update_warning() -> void:
	var lines: Array = []
	if SaveManager.has_save():
		var p := SaveManager.load_profile()
		lines.append(I18n.t("Starting over replaces your current journey (%d XP). Achievements and stats reset too.") % p.xp)
	if skip_basics.button_pressed:
		lines.append(I18n.t("You'll start at \"Needle, meet haystack\" (grep, pipes, permissions). The basics are marked as skipped."))
	warning.text = "\n".join(PackedStringArray(lines))


func _begin() -> void:
	journey_requested.emit(_selected_difficulty, skip_basics.button_pressed and _selected_difficulty != "beginner")


func _open_achievements() -> void:
	_show_page(achievements_page)
	for c in ach_list.get_children():
		c.queue_free()
	var system := AchievementSystem.load_default(SaveManager.load_profile())
	ach_heading.text = I18n.t("Achievements  %d/%d") % [system.unlocked_count(), system.definitions.size()]
	for def in system.definitions:
		var unlocked := system.is_unlocked(def.id)
		var hidden: bool = def.get("hidden", false) and not unlocked
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel" if unlocked else &"LockedCardPanel"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var icon := Label.new()
		icon.text = "??" if hidden else str(def.get("icon", "★"))
		icon.custom_minimum_size = Vector2(56, 0)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.theme_type_variation = &"VioletLabel" if unlocked else &"FaintLabel"
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := Label.new()
		t.text = I18n.t("Hidden achievement") if hidden else I18n.t(str(def.title))
		t.theme_type_variation = &"" if unlocked else &"DimLabel"
		var d := Label.new()
		d.text = I18n.t("Keep experimenting. Unusual solutions get noticed.") if hidden else I18n.t(str(def.description))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.theme_type_variation = &"DimLabel" if unlocked else &"FaintLabel"
		col.add_child(t)
		col.add_child(d)
		row.add_child(icon)
		row.add_child(col)
		card.add_child(row)
		ach_list.add_child(card)
	%AchBack.grab_focus()


func _build_settings() -> void:
	for sp in SPEEDS:
		speed.add_item(I18n.t(sp.capitalize()))
	for f in FONT_SIZES:
		font_size.add_item("%d px" % f)
	for d in DifficultySettings.all():
		difficulty_option.add_item(d.label)
	speed.item_selected.connect(func(i):
		Game.profile.settings["text_speed"] = SPEEDS[i]
		Game.save_now())
	font_size.item_selected.connect(func(i):
		Game.profile.settings["font_size"] = FONT_SIZES[i]
		Game.save_now()
		settings_changed.emit())
	difficulty_option.item_selected.connect(func(i):
		Game.set_difficulty(DifficultySettings.all()[i].id))


func _open_settings() -> void:
	_show_page(settings_page)
	var s: Dictionary = Game.profile.settings
	speed.select(maxi(0, SPEEDS.find(s.get("text_speed", "fast"))))
	font_size.select(maxi(0, FONT_SIZES.find(int(s.get("font_size", 17)))))
	var ids: Array = []
	for d in DifficultySettings.all():
		ids.append(d.id)
	difficulty_option.select(maxi(0, ids.find(Game.profile.difficulty)))
	difficulty_option.disabled = not Game.profile.started
	save_info.text = I18n.t("Progress is saved locally in %s") % ProjectSettings.globalize_path(SaveManager.save_path)
	_cancel_reset()
	speed.grab_focus()


func _cancel_reset() -> void:
	reset_confirm.visible = false
	reset_button.visible = true


func _do_reset() -> void:
	Game.reset_progress()
	_cancel_reset()
	save_info.text = I18n.t("Progress deleted. Fresh start.")
	reset_button.grab_focus()
