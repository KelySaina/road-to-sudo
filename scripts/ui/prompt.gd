extends Control
## A small modal for one line of (masked) input — su's password prompt. Opened
## via EventBus.prompt_requested; the answer goes back through Game.resolve_prompt.
## Enter submits, Esc / Ctrl-C cancels. Like the other overlays, the command that
## asked for it has already returned; this just collects the line.

signal answered(text: String)
signal cancelled()

var _field: LineEdit
var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.ACCENT_DIM, 10, 1, 22))
	card.custom_minimum_size = Vector2(460, 0)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	_label = Label.new()
	_label.add_theme_font_override("font", UiTheme.font())
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(_label)

	_field = LineEdit.new()
	_field.secret = true
	_field.secret_character = "•"
	_field.add_theme_font_override("font", UiTheme.font())
	_field.add_theme_font_size_override("font_size", 16)
	_field.add_theme_color_override("font_color", UiTheme.TEXT)
	_field.add_theme_color_override("caret_color", UiTheme.ACCENT)
	_field.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PANEL_ALT, UiTheme.BORDER, 6, 1, 8))
	_field.add_theme_stylebox_override("focus", UiTheme.box(UiTheme.PANEL_ALT, UiTheme.ACCENT_DIM, 6, 1, 8))
	vb.add_child(_field)
	_field.text_submitted.connect(_on_submit)

	var hint := Label.new()
	hint.text = I18n.t("Enter to confirm · Esc to cancel")
	hint.add_theme_font_override("font", UiTheme.font())
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiTheme.FAINT)
	vb.add_child(hint)


func ask(label_text: String) -> void:
	_label.text = label_text
	_field.text = ""
	visible = true
	_field.grab_focus()


func _on_submit(text: String) -> void:
	visible = false
	answered.emit(text)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or (event.keycode == KEY_C and event.ctrl_pressed):
			get_viewport().set_input_as_handled()
			visible = false
			cancelled.emit()
