class_name UiTheme
extends RefCounted
## The whole look, built in code: palette, fonts, styleboxes and the
## type variations scenes refer to (theme_type_variation = "DimLabel"...).

# Neon: vivid cyan/magenta/green on a deep violet-black. Bright accents, dark ground.
const BG := Color("070510")
const PANEL := Color("0e0b1e")
const PANEL_ALT := Color("141031")
const PANEL_HOVER := Color("1f1842")
const TERMINAL_BG := Color("08060f")
const BORDER := Color("2d2358")
const TEXT := Color("e9ecff")
const DIM := Color("8a8fce")
const FAINT := Color("555a93")
const ACCENT := Color("00e5ff") # neon cyan
const ACCENT_DIM := Color("128f9e")
const VIOLET := Color("c15bff") # neon magenta-violet
const WARN := Color("ffc53d") # neon amber
const ERROR := Color("ff2e63") # neon rose
const SUCCESS := Color("2bffb0") # neon green
const INFO := Color("4db8ff") # neon blue

## Output style name -> color (terminal chunks, narration kinds).
const STYLE_COLORS := {
	"": TEXT, "dir": INFO, "exec": SUCCESS, "hidden": DIM, "meta": DIM, "dim": DIM,
	"header": VIOLET, "match": WARN, "path": VIOLET, "warn": WARN, "err": ERROR,
	"tip": ACCENT, "solution": WARN, "story": TEXT, "reaction": VIOLET,
	"warning": WARN, "success": SUCCESS, "objective": ACCENT, "rule": FAINT,
}

const MONO_FAMILIES := ["JetBrains Mono", "Fira Code", "Cascadia Code", "Source Code Pro", "Ubuntu Mono", "DejaVu Sans Mono", "Menlo", "Consolas", "Liberation Mono", "monospace"]
const BUNDLED_REGULAR := "res://assets/fonts/mono-regular.ttf"
const BUNDLED_BOLD := "res://assets/fonts/mono-bold.ttf"


static func hex(style: String) -> String:
	return "#" + (STYLE_COLORS.get(style, TEXT) as Color).to_html(false)


static func font(bold: bool = false) -> Font:
	var bundled := BUNDLED_BOLD if bold else BUNDLED_REGULAR
	if ResourceLoader.exists(bundled):
		return load(bundled)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(MONO_FAMILIES)
	f.font_weight = 700 if bold else 400
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	return f


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 8, border_width: int = 1, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func build(size: int = 17) -> Theme:
	var t := Theme.new()
	var regular := font(false)
	var bold := font(true)
	t.default_font = regular
	t.default_font_size = size

	t.set_color("font_color", "Label", TEXT)
	_variation(t, "DimLabel", "Label", DIM, size - 2)
	_variation(t, "FaintLabel", "Label", FAINT, size - 3)
	_variation(t, "AccentLabel", "Label", ACCENT, size)
	_variation(t, "VioletLabel", "Label", VIOLET, size)
	_variation(t, "HeadingLabel", "Label", TEXT, size + 5)
	_variation(t, "TitleLabel", "Label", ACCENT, size * 3)
	t.set_font("font", "HeadingLabel", bold)
	t.set_font("font", "TitleLabel", bold)
	_variation(t, "CapsLabel", "Label", FAINT, size - 4)

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 10, 1, 14))
	t.set_type_variation("TerminalPanel", "PanelContainer")
	t.set_stylebox("panel", "TerminalPanel", box(TERMINAL_BG, BORDER, 10, 1, 0))
	t.set_type_variation("TitleBarPanel", "PanelContainer")
	var bar := box(PANEL_ALT, Color.TRANSPARENT, 0, 0, 8)
	bar.corner_radius_top_left = 10
	bar.corner_radius_top_right = 10
	bar.border_color = BORDER
	bar.border_width_bottom = 1
	t.set_stylebox("panel", "TitleBarPanel", bar)
	t.set_type_variation("ChipPanel", "PanelContainer")
	t.set_stylebox("panel", "ChipPanel", box(PANEL_ALT, BORDER, 6, 1, 4))
	t.set_type_variation("NewChipPanel", "PanelContainer")
	t.set_stylebox("panel", "NewChipPanel", box(Color(ACCENT, 0.12), ACCENT_DIM, 6, 1, 4))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", box(PANEL_ALT, BORDER, 8, 1, 12))
	t.set_type_variation("LockedCardPanel", "PanelContainer")
	t.set_stylebox("panel", "LockedCardPanel", box(PANEL, Color(BORDER, 0.6), 8, 1, 12))
	t.set_type_variation("ToastPanel", "PanelContainer")
	t.set_stylebox("panel", "ToastPanel", box(PANEL_ALT, VIOLET, 10, 1, 14))

	# Buttons
	t.set_stylebox("normal", "Button", box(PANEL_ALT, BORDER, 8, 1, 10))
	t.set_stylebox("hover", "Button", box(PANEL_HOVER, ACCENT_DIM, 8, 1, 10))
	t.set_stylebox("pressed", "Button", box(Color(ACCENT, 0.14), ACCENT, 8, 1, 10))
	t.set_stylebox("disabled", "Button", box(PANEL, Color(BORDER, 0.5), 8, 1, 10))
	var focus := box(Color.TRANSPARENT, ACCENT, 8, 2, 10)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_type_variation("MenuButtonBig", "Button")
	t.set_font_size("font_size", "MenuButtonBig", size + 1)
	t.set_type_variation("GhostButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "GhostButton", box(Color.TRANSPARENT, Color.TRANSPARENT, 6, 0, 6))
	t.set_stylebox("focus", "GhostButton", focus)
	t.set_color("font_color", "GhostButton", DIM)
	t.set_font_size("font_size", "GhostButton", size - 2)

	for type in ["OptionButton", "CheckBox"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT)
		t.set_color("font_focus_color", type, ACCENT)
		t.set_color("font_pressed_color", type, ACCENT)
	t.set_stylebox("normal", "OptionButton", box(PANEL_ALT, BORDER, 8, 1, 8))
	t.set_stylebox("hover", "OptionButton", box(PANEL_HOVER, ACCENT_DIM, 8, 1, 8))
	t.set_stylebox("pressed", "OptionButton", box(PANEL_HOVER, ACCENT, 8, 1, 8))
	t.set_stylebox("focus", "OptionButton", focus)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, 6, 0, 6))
	t.set_stylebox("focus", "CheckBox", focus)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_ALT, BORDER, 8, 1, 6))
	t.set_stylebox("hover", "PopupMenu", box(PANEL_HOVER, Color.TRANSPARENT, 4, 0, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)

	# Text input: flat, the terminal draws its own frame.
	t.set_stylebox("normal", "LineEdit", StyleBoxEmpty.new())
	t.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	t.set_stylebox("read_only", "LineEdit", StyleBoxEmpty.new())
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.25))
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	t.set_constant("caret_width", "LineEdit", 2)

	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("selection_color", "RichTextLabel", Color(ACCENT, 0.22))
	t.set_font("normal_font", "RichTextLabel", regular)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font("mono_font", "RichTextLabel", regular)
	for key in ["normal_font_size", "bold_font_size", "mono_font_size", "italics_font_size"]:
		t.set_font_size(key, "RichTextLabel", size)
	t.set_constant("line_separation", "RichTextLabel", 3)

	t.set_stylebox("background", "ProgressBar", box(PANEL, BORDER, 4, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 4, 0, 0))

	for bar_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar_type, box(Color.TRANSPARENT, Color.TRANSPARENT, 4, 0, 2))
		t.set_stylebox("grabber", bar_type, box(BORDER, Color.TRANSPARENT, 4, 0, 3))
		t.set_stylebox("grabber_highlight", bar_type, box(FAINT, Color.TRANSPARENT, 4, 0, 3))
		t.set_stylebox("grabber_pressed", bar_type, box(ACCENT_DIM, Color.TRANSPARENT, 4, 0, 3))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_ALT, BORDER, 6, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("separator", "HSeparator", box(BORDER, Color.TRANSPARENT, 0, 0, 0))
	t.set_constant("separation", "HSeparator", 12)
	return t


static func _variation(t: Theme, name: String, base: String, color: Color, font_size: int) -> void:
	t.set_type_variation(name, base)
	t.set_color("font_color", name, color)
	t.set_font_size("font_size", name, font_size)
