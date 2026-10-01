extends Control
## Title screen. Emits intents; Main performs them.

signal journey_requested(difficulty: String, skip_basics: bool)
signal continue_requested()
signal practice_requested()
signal adventure_requested()
signal settings_changed()

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

var _language_option: OptionButton


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
	_build_difficulties()
	_build_settings()
	_apply_locale_text()
	_show_home()


## Sets every menu label from the current locale (English falls through
## unchanged). Called on load and whenever the language changes.
func _apply_locale_text() -> void:
	start_button.text = Loc.t("Start Journey")
	continue_button.text = Loc.t("Continue")
	practice_button.text = Loc.t("Practice Lab")
	%AdventureButton.text = Loc.t("Adventure — The Ascent to Root")
	%AchievementsButton.text = Loc.t("Achievements")
	%SettingsButton.text = Loc.t("Settings")
	%ExitButton.text = Loc.t("Exit")
	%BeginButton.text = Loc.t("Begin  ⏎")
	skip_basics.text = Loc.t("I know the basics — skip to the first real problem")
	ach_heading.text = Loc.t("Achievements")
	reset_button.text = Loc.t("Reset all progress…")
	for b in [%BackButton, %AchBack, %SetBack]:
		b.text = Loc.t("← Back")
	var grid := speed.get_parent()
	grid.get_child(0).text = Loc.t("Narration speed")
	grid.get_child(2).text = Loc.t("Text size")
	grid.get_child(4).text = Loc.t("Difficulty (current journey)")
	if _language_option != null:
		(_language_option.get_parent().get_child(6) as Label).text = Loc.t("Language")


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
		var where := c.title if c != null else "journey complete"
		continue_button.text = "Continue   ·  %s · %d XP · %s" % [Progression.new(p).current_rank().name, p.xp, where]
	else:
		continue_button.text = "Continue"
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
		lines.append("Starting over replaces your current journey (%d XP). Achievements and stats reset too." % p.xp)
	if skip_basics.button_pressed:
		lines.append("You'll start at \"Needle, meet haystack\" (grep, pipes, permissions). The basics are marked as skipped.")
	warning.text = "\n".join(PackedStringArray(lines))


func _begin() -> void:
	journey_requested.emit(_selected_difficulty, skip_basics.button_pressed and _selected_difficulty != "beginner")


func _open_achievements() -> void:
	_show_page(achievements_page)
	for c in ach_list.get_children():
		c.queue_free()
	var system := AchievementSystem.load_default(SaveManager.load_profile())
	ach_heading.text = "Achievements  %d/%d" % [system.unlocked_count(), system.definitions.size()]
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
		t.text = "Hidden achievement" if hidden else def.title
		t.theme_type_variation = &"" if unlocked else &"DimLabel"
		var d := Label.new()
		d.text = "Keep experimenting. Unusual solutions get noticed." if hidden else def.description
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
	for s in SPEEDS:
		speed.add_item(s.capitalize())
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
	# Language row, appended to the settings grid (label + dropdown).
	var grid := speed.get_parent()
	var lang_label := Label.new()
	lang_label.text = Loc.t("Language")
	grid.add_child(lang_label)
	_language_option = OptionButton.new()
	_language_option.add_item("English")
	_language_option.add_item("Français")
	grid.add_child(_language_option)
	_language_option.item_selected.connect(func(i):
		Game.profile.settings["language"] = "fr" if i == 1 else "en"
		Loc.set_locale(str(Game.profile.settings["language"]))
		Game.save_now()
		_apply_locale_text()
		settings_changed.emit())


func _open_settings() -> void:
	_show_page(settings_page)
	var s: Dictionary = Game.profile.settings
	speed.select(maxi(0, SPEEDS.find(s.get("text_speed", "fast"))))
	font_size.select(maxi(0, FONT_SIZES.find(int(s.get("font_size", 17)))))
	if _language_option != null:
		_language_option.select(1 if Loc.locale == "fr" else 0)
	var ids: Array = []
	for d in DifficultySettings.all():
		ids.append(d.id)
	difficulty_option.select(maxi(0, ids.find(Game.profile.difficulty)))
	difficulty_option.disabled = not Game.profile.started
	save_info.text = "Progress is saved locally in %s" % ProjectSettings.globalize_path(SaveManager.save_path)
	_cancel_reset()
	speed.grab_focus()


func _cancel_reset() -> void:
	reset_confirm.visible = false
	reset_button.visible = true


func _do_reset() -> void:
	Game.reset_progress()
	_cancel_reset()
	save_info.text = "Progress deleted. Fresh start."
	reset_button.grab_focus()
