class_name Hazard
extends Area2D
## Something that sets you back rather than kills you.
##
## Adventure mode has no HP and no death — this is a game about learning Linux,
## and a course you can lose is a course you stop playing. Touching a hazard
## costs you the few seconds since the last ground you stood on, nothing more.
##
## Three kinds, in the order the worlds introduce them:
##   SPIKES  static, always dangerous — a strip of ground you must jump.
##   ROVER   patrols a stretch, so you have to pick your moment.
##   BURST   pulses on and off on a timer, so you have to read a rhythm.

enum Kind { SPIKES, ROVER, BURST }

const TILE := 48
const ROVER_SPEED := 82.0
const BURST_PERIOD := 2.4    # seconds for a full off/on cycle
const BURST_DUTY := 0.42     # fraction of that cycle it is dangerous
const FPS := 7.0

var kind: Kind = Kind.SPIKES

var _sprite: Sprite2D
var _halo: Sprite2D
var _frames: Array = []
var _t := 0.0
var _min_x := 0.0
var _max_x := 0.0
var _dir := 1.0


static func make(p_kind: Kind, cell: Vector2i) -> Hazard:
	var h := Hazard.new()
	h.kind = p_kind
	h.position = Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
	return h


## Give a rover the stretch it owns, in tile columns.
func patrol(from_col: int, to_col: int) -> void:
	_min_x = (from_col + 0.5) * TILE
	_max_x = (to_col + 0.5) * TILE


func _ready() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 1        # the player's body
	z_index = 7

	var art: Array = {
		Kind.SPIKES: ["spikes"],
		Kind.ROVER: ["rover_0", "rover_1", "rover_2", "rover_3"],
		Kind.BURST: ["burst_0", "burst_1", "burst_2", "burst_3"],
	}[kind]
	for name in art:
		_frames.append(SpriteFactory.texture(name))

	# A danger halo behind the art. The tiles come in five colours and the hazard
	# art only one, so on some worlds it would otherwise sit too close to the
	# ground it is standing on; this keeps "that will hurt" readable everywhere.
	_halo = Sprite2D.new()
	_halo.texture = SpriteFactory.glow(UiTheme.ERROR)
	_halo.scale = Vector2(5.5, 4.2)
	_halo.modulate.a = 0.0
	add_child(_halo)

	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = _frames[0]
	_sprite.scale = Vector2(3, 3)
	add_child(_sprite)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Forgiving boxes: smaller than the art, so a near miss reads as a miss.
	match kind:
		Kind.SPIKES:
			rect.size = Vector2(38, 22)
			shape.position = Vector2(0, 12)
		Kind.ROVER:
			rect.size = Vector2(40, 30)
			shape.position = Vector2(0, 6)
		Kind.BURST:
			rect.size = Vector2(36, 34)
			shape.position = Vector2(0, 4)
	shape.shape = rect
	add_child(shape)


func _process(delta: float) -> void:
	_t += delta
	if _frames.size() > 1:
		_sprite.texture = _frames[int(_t * FPS) % _frames.size()]
	# The halo breathes while the thing is live, and goes out when it isn't.
	var want: float = (0.30 + 0.10 * sin(_t * 4.0)) if is_live() else 0.0
	_halo.modulate.a = move_toward(_halo.modulate.a, want, delta * 3.0)
	match kind:
		Kind.ROVER:
			position.x += _dir * ROVER_SPEED * delta
			if position.x <= _min_x:
				position.x = _min_x; _dir = 1.0
			elif position.x >= _max_x:
				position.x = _max_x; _dir = -1.0
			_sprite.flip_h = _dir < 0.0
		Kind.BURST:
			# Fade in before it bites, so the rhythm is readable rather than a
			# gotcha: it is only dangerous once it is fully lit.
			var phase := fmod(_t, BURST_PERIOD) / BURST_PERIOD
			var live := phase < BURST_DUTY
			var warn := phase < BURST_DUTY + 0.12
			_sprite.modulate.a = 1.0 if live else (0.45 if warn else 0.18)
			_sprite.scale = Vector2(3, 3) if live else Vector2(2.3, 2.3)


## Is this thing dangerous right now? Only a lit BURST is; the others always are.
func is_live() -> bool:
	if kind != Kind.BURST:
		return true
	return fmod(_t, BURST_PERIOD) / BURST_PERIOD < BURST_DUTY
