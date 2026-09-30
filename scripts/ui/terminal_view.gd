extends PanelContainer
## The terminal widget: scrollback, prompt, history and Tab completion.
## It renders ExecutionOutcomes and narration; it never runs commands.

signal submitted(line: String)

const MAX_PARAGRAPHS := 6000
const SPEEDS := {"instant": 0.0, "fast": 1400.0, "normal": 420.0} # characters per second

## func(line: String) -> {"line": String, "candidates": Array}
var completer: Callable
## func(line: String) -> String (one-line inline help, "" for none)
var describer: Callable
## Shared with ShellSession.history, so ↑ recalls what the shell recorded.
var history: Array = []
var chars_per_second: float = SPEEDS.fast

var _history_index := -1
var _draft := ""
var _queue: Array = [] # {"text": String, "color": String}
var _budget := 0.0
var _prompt_bb := ""

@onready var output: RichTextLabel = %Output
@onready var input: LineEdit = %Input
@onready var prompt_user: Label = %PromptUser
@onready var prompt_path: Label = %PromptPath
@onready var prompt_symbol: Label = %PromptSymbol
@onready var title_text: Label = %TitleText
@onready var suggestion: Label = %Suggestion
@onready var dots: Label = %Dots


func _ready() -> void:
	input.text_submitted.connect(_on_submitted)
	input.text_changed.connect(_on_text_changed)
	input.gui_input.connect(_on_input_gui)
	# Keep Tab inside the prompt instead of moving focus.
	input.focus_next = input.get_path()
	input.focus_previous = input.get_path()
	prompt_path.add_theme_color_override("font_color", UiTheme.INFO)
	dots.add_theme_color_override("font_color", UiTheme.FAINT)
	suggestion.text = ""
	focus_input.call_deferred()


func focus_input() -> void:
	if is_inside_tree():
		input.grab_focus()


func set_speed(speed_name: String) -> void:
	chars_per_second = SPEEDS.get(speed_name, SPEEDS.fast)


func set_prompt(user: String, host: String, path: String, symbol: String) -> void:
	prompt_user.text = "%s@%s" % [user, host]
	prompt_user.add_theme_color_override("font_color", UiTheme.ERROR if user == "root" else UiTheme.ACCENT)
	prompt_path.text = ":" + path
	prompt_symbol.text = symbol + " "
	title_text.text = "%s@%s: %s" % [user, host, path]
	var user_color := UiTheme.ERROR if user == "root" else UiTheme.ACCENT
	_prompt_bb = "[color=#%s]%s@%s[/color][color=#%s]:%s[/color]%s " % [
		user_color.to_html(false), _esc(user), _esc(host), UiTheme.INFO.to_html(false), _esc(path), symbol]


# --- printing ------------------------------------------------------------------

func print_outcome(outcome: ExecutionOutcome) -> void:
	flush()
	if outcome.clear_screen:
		output.clear()
	for c in outcome.chunks:
		var style: String = c.style
		if c.stream == "err":
			style = "err"
		_append(c.text, UiTheme.hex(style))
	_trim()


## Narration: typed out character by character (unless speed is instant),
## word-wrapped with a hanging indent so paragraphs stay readable.
func type_text(text: String, style: String = "story") -> void:
	_queue.append({"text": wrap_text(text, _columns()) + "\n", "color": UiTheme.hex(style)})
	if chars_per_second <= 0.0:
		flush()


## Printed immediately, no typing effect.
func print_text(text: String, style: String = "") -> void:
	flush()
	_append(text + "\n", UiTheme.hex(style))


func print_rule(label: String) -> void:
	var width := 64
	var inner := " %s " % label
	var left := 3
	var right := maxi(3, width - left - inner.length())
	print_text("─".repeat(left) + inner + "─".repeat(right), "rule")


func _columns() -> int:
	var f := output.get_theme_font("normal_font")
	var char_width := f.get_char_size(77, output.get_theme_font_size("normal_font_size")).x
	if char_width <= 0.0 or output.size.x <= 0.0:
		return 0
	return int((output.size.x - 16.0) / char_width)


static var _label_regex: RegEx


## Wraps at `columns`; continuation lines align under the text that follows
## the leading spaces and any bullet or UPPERCASE label ("OBJECTIVE  ").
static func wrap_text(text: String, columns: int) -> String:
	if columns < 20 or text.length() <= columns:
		return text
	if _label_regex == null:
		_label_regex = RegEx.create_from_string("^(\\s*)((?:[›✔★▸•] )|(?:[A-Z][A-Z0-9/ ]+?  ))?")
	var m := _label_regex.search(text)
	var hang := m.get_string(1).length() + m.get_string(2).length() if m != null else 0
	if hang > columns / 2:
		hang = 2
	var pad := " ".repeat(hang)
	var lead := m.get_string(1) if m != null else ""
	var lines: Array = []
	var current := lead
	for word in text.strip_edges(true, false).split(" "):
		var candidate: String = current + word if current.strip_edges() == "" else current + " " + word
		if candidate.length() > columns and current.strip_edges() != "":
			lines.append(current)
			current = pad + word
		else:
			current = candidate
	lines.append(current)
	return "\n".join(PackedStringArray(lines))


func clear_screen() -> void:
	_queue.clear()
	output.clear()


func flush() -> void:
	for item in _queue:
		_append(item.text, item.color)
	_queue.clear()


func is_typing() -> bool:
	return not _queue.is_empty()


func _process(delta: float) -> void:
	_keep_focus()
	if _queue.is_empty():
		_budget = 0.0
		return
	_budget += delta * chars_per_second
	while _budget >= 1.0 and not _queue.is_empty():
		var item: Dictionary = _queue[0]
		var take := mini(int(_budget), item.text.length())
		_append(item.text.substr(0, take), item.color)
		item.text = item.text.substr(take)
		_budget -= take
		if item.text == "":
			_queue.pop_front()


## Reclaims focus only when it has fallen to nobody (the state that eats the
## next keystroke), never from a control the player actually clicked, and not
## mid drag-select of the output.
func _keep_focus() -> void:
	if not is_visible_in_tree() or input.has_focus():
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# Nothing else in the terminal view is focusable (buttons are focus_mode
	# NONE), so it is safe to reclaim focus whenever it has drifted away.
	input.grab_focus()


func _append(text: String, color: String) -> void:
	if text == "":
		return
	output.append_text("[color=%s]%s[/color]" % [color, _esc(text)])


func _trim() -> void:
	var excess := output.get_paragraph_count() - MAX_PARAGRAPHS
	for i in maxi(0, excess):
		output.remove_paragraph(0)


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


# --- input ---------------------------------------------------------------------

func _on_submitted(text: String) -> void:
	flush()
	output.append_text(_prompt_bb + "[color=%s]%s[/color]\n" % [UiTheme.hex(""), _esc(text)])
	input.clear()
	suggestion.text = ""
	_history_index = -1
	_draft = ""
	submitted.emit(text)
	# Processing the line (done synchronously in the emit above) can move focus
	# while rebuilding UI; take it straight back so the next keystroke lands in
	# the prompt, not on a re-focus that eats the character.
	if is_visible_in_tree():
		input.grab_focus()


func _on_text_changed(text: String) -> void:
	suggestion.text = describer.call(text) if describer.is_valid() else ""


func _on_input_gui(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := event as InputEventKey
	var handled := true
	if key.keycode == KEY_TAB:
		_complete()
	elif key.keycode == KEY_UP:
		_history_step(-1)
	elif key.keycode == KEY_DOWN:
		_history_step(1)
	elif key.keycode == KEY_PAGEUP:
		output.get_v_scroll_bar().value -= output.size.y * 0.8
	elif key.keycode == KEY_PAGEDOWN:
		output.get_v_scroll_bar().value += output.size.y * 0.8
	elif key.ctrl_pressed and key.keycode == KEY_L:
		clear_screen()
	elif key.ctrl_pressed and key.keycode == KEY_C and not input.has_selection():
		flush()
		output.append_text(_prompt_bb + _esc(input.text) + "[color=%s]^C[/color]\n" % UiTheme.hex("dim"))
		input.clear()
		_history_index = -1
	elif key.ctrl_pressed and key.keycode == KEY_U:
		input.text = input.text.substr(input.caret_column)
		input.caret_column = 0
	elif key.ctrl_pressed and key.keycode == KEY_A:
		input.caret_column = 0
	elif key.ctrl_pressed and key.keycode == KEY_E:
		input.caret_column = input.text.length()
	else:
		handled = false
	if handled:
		input.accept_event()


func _complete() -> void:
	if not completer.is_valid():
		return
	var before := input.text.substr(0, input.caret_column)
	var after := input.text.substr(input.caret_column)
	var result: Dictionary = completer.call(before)
	if result.candidates.is_empty():
		input.text = result.line + after
		input.caret_column = result.line.length()
		_on_text_changed(input.text)
		return
	flush()
	output.append_text(_prompt_bb + _esc(input.text) + "\n")
	_append("  ".join(PackedStringArray(result.candidates)) + "\n", UiTheme.hex("dim"))


func _history_step(direction: int) -> void:
	if history.is_empty():
		return
	if _history_index == -1:
		if direction > 0:
			return
		_draft = input.text
		_history_index = history.size()
	_history_index = clampi(_history_index + direction, 0, history.size())
	input.text = _draft if _history_index == history.size() else str(history[_history_index])
	if _history_index == history.size():
		_history_index = -1
	input.caret_column = input.text.length()
	_on_text_changed(input.text)


## Typing anywhere in the game screen goes to the prompt. If focus had briefly
## drifted, grab it AND act on the key in the same event, so no keystroke is
## ever eaten just re-focusing (the "I have to click / press Enter twice before
## I can type" bug). Enter, Backspace and printable characters are all handled.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (is_visible_in_tree() and event is InputEventKey and event.pressed and not input.has_focus()):
		return
	input.grab_focus()
	var key := event as InputEventKey
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_on_submitted(input.text)
		accept_event()
	elif key.keycode == KEY_BACKSPACE:
		if input.caret_column > 0:
			var col := input.caret_column
			input.text = input.text.substr(0, col - 1) + input.text.substr(col)
			input.caret_column = col - 1
			_on_text_changed(input.text)
		accept_event()
	elif key.unicode >= 32 and not key.ctrl_pressed and not key.meta_pressed:
		input.insert_text_at_caret(String.chr(key.unicode))
		_on_text_changed(input.text)
		accept_event()
