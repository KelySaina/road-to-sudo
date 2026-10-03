extends Control
## A read-only full-screen viewer, used for two interactive programs that the
## terminal couldn't do before:
##   * less  — page through a file or piped text (scroll, /search, q to quit)
##   * tail -f — follow a log: the tail, then new lines streaming in live
## Like the editor, a command asks the game to open this (EventBus.viewer_requested
## with {mode:"page"|"follow", ...}); it never edits anything.

signal closed()

var _text: TextEdit
var _title: Label
var _footer: Label

var _mode := "page"
var _lines: PackedStringArray = []
var _search := ""
var _searching := false
var _last_match := -1

# follow mode
var _feed_timer: Timer
var _feed_i := 0
var _feed_clock := 0
var _feed_host := "host"
var _feed_kind := "sys"

const PAGE := 18


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
	_text.editable = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.scroll_smooth = false
	_text.add_theme_font_override("font", UiTheme.font())
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", UiTheme.TEXT)
	_text.add_theme_color_override("font_readonly_color", UiTheme.TEXT)
	_text.add_theme_color_override("selection_color", UiTheme.ACCENT_DIM)
	_text.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 6, 1, 12))
	_text.add_theme_stylebox_override("read_only", UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 6, 1, 12))
	vb.add_child(_text)

	_footer = _bar(vb, UiTheme.PANEL_ALT, UiTheme.DIM, false)

	_feed_timer = Timer.new()
	_feed_timer.wait_time = 0.85
	_feed_timer.timeout.connect(_tick_feed)
	add_child(_feed_timer)


## Open a static pager over `content` (less). `title` is the file name or "(stdin)".
func page(title: String, content: String) -> void:
	_mode = "page"
	_feed_timer.stop()
	_lines = _split(content)
	_text.text = content
	_title.text = "  %s   (less)" % title
	_set_footer()
	_searching = false
	_search = ""
	_last_match = -1
	visible = true
	_text.grab_focus()
	_text.scroll_vertical = 0


## Open a follow view (tail -f): show `content` (the tail), then stream new lines.
func follow(title: String, content: String, kind: String) -> void:
	_mode = "follow"
	_lines = _split(content)
	_text.text = content
	_feed_kind = kind
	_feed_i = 0
	_feed_clock = 9 * 3600
	_feed_host = str(title).get_file().get_slice(".", 0)
	if _feed_host == "":
		_feed_host = "host"
	_title.text = "  %s   (tail -f)" % title
	_footer.text = "  " + I18n.t("following — new lines appear live…   ^C or q to stop")
	visible = true
	_text.grab_focus()
	_to_bottom()
	_feed_timer.start()


func _tick_feed() -> void:
	if not visible or _mode != "follow":
		return
	_feed_clock += randi_range(1, 4)
	var line := _next_feed_line()
	if _text.text == "":
		_text.text = line
	else:
		_text.text += "\n" + line
	_to_bottom()


func _next_feed_line() -> String:
	_feed_i += 1
	var h := (_feed_clock / 3600) % 24
	var m := (_feed_clock / 60) % 60
	var s := _feed_clock % 60
	var stamp := "%02d:%02d:%02d" % [h, m, s]
	var pid := 1000 + (_feed_i * 7) % 9000
	var msg: String
	match _feed_kind:
		"auth":
			var who: String = ["root", "deploy", "admin", "backup"][_feed_i % 4]
			var ip := "203.0.113.%d" % (10 + _feed_i % 240)
			msg = ["sshd[%d]: Accepted publickey for %s from %s port 55%02d" % [pid, who, ip, _feed_i % 100],
				"sshd[%d]: pam_unix(sshd:session): session opened for user %s" % [pid, who],
				"sshd[%d]: Failed password for invalid user %s from %s" % [pid, who, ip]][_feed_i % 3]
		"http":
			var paths := ["/", "/health", "/api/v1/status", "/assets/app.js", "/login"]
			var codes := [200, 200, 304, 200, 502]
			msg = "nginx: 10.0.0.%d - - \"GET %s HTTP/1.1\" %d" % [_feed_i % 250, paths[_feed_i % 5], codes[_feed_i % 5]]
		_:
			msg = ["systemd[1]: Started Daily apt download activities.",
				"cron[%d]: (root) CMD (/usr/sbin/logrotate)" % pid,
				"kernel: [%d.%03d] TCP: request_sock_TCP: dropping" % [_feed_clock, _feed_i % 1000],
				"systemd[1]: Starting Cleanup of Temporary Directories..."][_feed_i % 4]
	return "%s %s %s" % [stamp, _feed_host, msg]


func _to_bottom() -> void:
	_text.scroll_vertical = maxf(0.0, float(_text.get_line_count()))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode

	if event.ctrl_pressed and k == KEY_C:
		_accept()
		_close()
		return

	if _searching:
		_accept()
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			_searching = false
			_find_next(int(_text.scroll_vertical))
		elif k == KEY_ESCAPE:
			_searching = false
			_search = ""
			_set_footer()
		elif k == KEY_BACKSPACE:
			_search = _search.substr(0, maxi(0, _search.length() - 1))
			_set_footer()
		elif event.unicode >= 32:
			_search += char(event.unicode)
			_set_footer()
		return

	match k:
		KEY_Q, KEY_ESCAPE:
			_accept()
			_close()
		KEY_DOWN, KEY_J:
			_accept()
			_scroll(1)
		KEY_UP, KEY_K:
			_accept()
			_scroll(-1)
		KEY_SPACE, KEY_PAGEDOWN, KEY_F:
			_accept()
			_scroll(PAGE)
		KEY_B, KEY_PAGEUP:
			_accept()
			_scroll(-PAGE)
		KEY_G:
			_accept()
			_text.scroll_vertical = float(_text.get_line_count()) if event.shift_pressed else 0.0
		KEY_HOME:
			_accept()
			_text.scroll_vertical = 0.0
		KEY_END:
			_accept()
			_to_bottom()
		KEY_SLASH:
			if _mode == "page":
				_accept()
				_searching = true
				_search = ""
				_set_footer()
		KEY_N:
			if _mode == "page" and _search != "":
				_accept()
				_find_next(int(_text.scroll_vertical) + (0 if event.shift_pressed else 1))


func _scroll(delta: int) -> void:
	var top := int(_text.scroll_vertical) + delta
	_text.scroll_vertical = float(clampi(top, 0, maxi(0, _text.get_line_count())))


func _find_next(from_line: int) -> void:
	if _search == "":
		return
	var needle := _search.to_lower()
	var n := _lines.size()
	for off in n:
		var i := (from_line + off) % n
		if _lines[i].to_lower().contains(needle):
			_text.scroll_vertical = float(i)
			_last_match = i
			_footer.text = "  /%s   — %s %d" % [_search, I18n.t("line"), i + 1]
			return
	_footer.text = "  /%s   — %s" % [_search, I18n.t("not found")]


func _set_footer() -> void:
	if _searching:
		_footer.text = "  /%s" % _search
	else:
		_footer.text = "  " + I18n.t("↑↓ scroll · Space/b page · g/G top/bottom · / search · q quit")


func _close() -> void:
	_feed_timer.stop()
	visible = false
	_searching = false
	closed.emit()


func _accept() -> void:
	get_viewport().set_input_as_handled()


func _split(content: String) -> PackedStringArray:
	var c := content
	if c.ends_with("\n"):
		c = c.substr(0, c.length() - 1)
	return c.split("\n")


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
