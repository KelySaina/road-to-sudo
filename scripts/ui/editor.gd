extends Control
## A small full-screen text editor, styled after nano. The `nano` command asks
## the game to open it (via EventBus.editor_requested); saving goes back through
## Game.apply_edit, which writes the file and re-grades the challenge. Built in
## code so it can be dropped onto any screen that hosts the terminal.

signal closed(saved: bool)

var _text: TextEdit
var _title: Label
var _status: Label
var _footer: Label

var _path := ""
var _display := ""
var _can_write := true
var _dirty := false
var _confirm_exit := false
var _saved_once := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = UiTheme.TERMINAL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	_title = _bar(vb, UiTheme.ACCENT, UiTheme.BG, true)

	_text = TextEdit.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.add_theme_font_override("font", UiTheme.font())
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", UiTheme.TEXT)
	_text.add_theme_color_override("caret_color", UiTheme.ACCENT)
	_text.add_theme_color_override("selection_color", UiTheme.ACCENT_DIM)
	_text.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 6, 1, 12))
	_text.add_theme_stylebox_override("focus", UiTheme.box(UiTheme.PANEL, UiTheme.ACCENT_DIM, 6, 1, 12))
	vb.add_child(_text)
	_text.text_changed.connect(_on_text_changed)

	_status = Label.new()
	_status.add_theme_font_override("font", UiTheme.font())
	_status.add_theme_font_size_override("font_size", 15)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_status)

	_footer = _bar(vb, UiTheme.PANEL_ALT, UiTheme.DIM, false)


## Open the editor on a file. `data` is the payload from the nano command.
func open(data: Dictionary) -> void:
	_path = str(data.get("path", ""))
	_display = str(data.get("display", _path))
	_can_write = bool(data.get("can_write", true))
	_text.text = str(data.get("content", ""))
	_dirty = false
	_confirm_exit = false
	_saved_once = false

	var tag := ""
	if not _can_write:
		tag = "   [ " + I18n.t("Read Only") + " ]"
	elif bool(data.get("is_new", false)):
		tag = "   ( " + I18n.t("New File") + " )"
	_title.text = "  GNU nano  —  %s%s" % [_display, tag]
	_footer.text = "  ^O %s      ^X %s      %s" % [I18n.t("Write Out"), I18n.t("Exit"), I18n.t("(Esc also exits)")]
	_set_status("")

	visible = true
	_text.grab_focus()
	_text.set_caret_line(0)
	_text.set_caret_column(0)


func _on_text_changed() -> void:
	_dirty = true
	if not _confirm_exit:
		_set_status("")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode

	if _confirm_exit:
		if k == KEY_Y:
			_accept()
			if _save():
				_close(true)
			else:
				_confirm_exit = false
		elif k == KEY_N:
			_accept()
			_close(false)
		elif k == KEY_ESCAPE:
			_accept()
			_confirm_exit = false
			_set_status("")
		return

	if event.ctrl_pressed and k == KEY_O:
		_accept()
		_save()
	elif (event.ctrl_pressed and k == KEY_X) or k == KEY_ESCAPE:
		_accept()
		_request_exit()


func _request_exit() -> void:
	if _dirty:
		_confirm_exit = true
		_set_status(I18n.t("Save modified buffer?   Y = yes    N = no    (Esc cancels)"), UiTheme.WARN)
	else:
		_close(_saved_once)


func _save() -> bool:
	var res: Dictionary = Game.apply_edit(_path, _text.text)
	if bool(res.get("ok", false)):
		_dirty = false
		_saved_once = true
		_set_status("[ " + I18n.t("Wrote %d line(s)") % int(res.get("lines", 0)) + " ]", UiTheme.SUCCESS)
		return true
	_set_status("[ " + I18n.t("Error writing: %s") % str(res.get("error", "could not write")) + " ]", UiTheme.ERROR)
	return false


func _close(saved: bool) -> void:
	visible = false
	_confirm_exit = false
	closed.emit(saved)


func _accept() -> void:
	get_viewport().set_input_as_handled()


func _set_status(text: String, color: Color = UiTheme.DIM) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


## A nano-style full-width bar (inverted title, dim footer).
func _bar(parent: Node, bg: Color, fg: Color, bold: bool) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(bg, Color.TRANSPARENT, 4, 0, 6))
	parent.add_child(panel)
	var label := Label.new()
	label.add_theme_font_override("font", UiTheme.font(bold))
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", fg)
	panel.add_child(label)
	return label
