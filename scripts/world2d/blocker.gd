class_name Blocker
extends StaticBody2D
## A door that blocks a passage until its condition is met (a node cleared or a
## flag held). Opens with a little fade once the player has earned it.

var data: Dictionary = {}
var _open := false
var _sprites: Array = []


func setup(door: Dictionary, tile: int) -> void:
	data = door
	collision_layer = 1
	collision_mask = 0
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for t in door.get("tiles", []):
		min_x = minf(min_x, t[0]); min_y = minf(min_y, t[1])
		max_x = maxf(max_x, t[0]); max_y = maxf(max_y, t[1])
		var s := Sprite2D.new()
		s.texture = SpriteFactory.texture("door")
		s.scale = Vector2(tile / 16.0, tile / 16.0)
		s.position = Vector2((t[0] + 0.5) * tile, (t[1] + 0.5) * tile)
		s.z_index = 5
		add_child(s)
		_sprites.append(s)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2((max_x - min_x + 1) * tile, (max_y - min_y + 1) * tile)
	shape.shape = rect
	shape.position = Vector2((min_x + max_x + 1) * 0.5 * tile, (min_y + max_y + 1) * 0.5 * tile)
	add_child(shape)


func refresh(state: AdventureState) -> void:
	if _open or not _met(state):
		return
	_open = true
	set_deferred("collision_layer", 0)
	for s in _sprites:
		var tw := create_tween()
		tw.tween_property(s, "modulate:a", 0.0, 0.4)
		tw.tween_callback(s.hide)


func is_open() -> bool:
	return _open


func _met(state: AdventureState) -> bool:
	if data.get("open", false):
		return true
	if data.has("needs_cleared"):
		return state.is_cleared(data.needs_cleared)
	if data.has("needs_flag"):
		return state.has_flag(data.needs_flag)
	return false
