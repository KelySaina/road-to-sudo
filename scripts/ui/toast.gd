extends PanelContainer
## A notification card that slides in, waits, and fades away.

const HOLD_SECONDS := 2.6

@onready var icon: Label = %Icon
@onready var kicker: Label = %Kicker
@onready var title_label: Label = %Title
@onready var body: Label = %Body


func setup(p_kicker: String, p_title: String, p_body: String, p_icon: String, color: Color) -> void:
	kicker.text = p_kicker
	title_label.text = p_title
	body.text = p_body
	icon.text = p_icon
	icon.add_theme_color_override("font_color", color)
	title_label.add_theme_color_override("font_color", color)


func _ready() -> void:
	modulate.a = 0.0
	position.y -= 12.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
