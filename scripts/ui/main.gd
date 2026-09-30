extends Control
## Root scene: applies the theme and swaps between menu and game screens.

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const GAME_SCENE := preload("res://scenes/main/game_screen.tscn")
const WORLD2D_SCENE := preload("res://scenes/world2d/world2d.tscn")

@onready var host: Control = %ScreenHost
@onready var toasts: VBoxContainer = %Toasts


func _ready() -> void:
	apply_theme()
	EventBus.menu_requested.connect(show_menu)
	show_menu()


func apply_theme() -> void:
	var size := int(Game.profile.settings.get("font_size", 17))
	theme = UiTheme.build(size)
	toasts.theme = theme # CanvasLayer children don't inherit the Control theme


func show_menu() -> void:
	$Background.visible = true
	var menu := MENU_SCENE.instantiate()
	_swap(menu)
	menu.journey_requested.connect(func(difficulty: String, skip: bool):
		Game.new_journey(difficulty, skip)
		_show_game("campaign", true))
	menu.continue_requested.connect(func():
		Game.continue_journey()
		_show_game("campaign", false))
	menu.practice_requested.connect(func():
		Game.start_practice()
		_show_game("practice", true))
	menu.adventure_requested.connect(func():
		var resumed: bool = Game.start_adventure2d()
		_show_world(resumed))
	menu.settings_changed.connect(apply_theme)


func _show_game(mode: String, fresh: bool) -> void:
	$Background.visible = true
	var screen := GAME_SCENE.instantiate()
	_swap(screen)
	screen.begin(mode, fresh)


func _show_world(resumed: bool) -> void:
	$Background.visible = false
	var world := WORLD2D_SCENE.instantiate()
	world.setup(resumed)
	for c in host.get_children():
		c.queue_free()
	host.add_child(world)


func _swap(screen: Control) -> void:
	for c in host.get_children():
		c.queue_free()
	host.add_child(screen)
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.25)
