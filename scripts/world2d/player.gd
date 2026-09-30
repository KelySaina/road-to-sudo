class_name Player2D
extends CharacterBody2D
## Side-on operator for the platforming worlds: run, jump, fall. Builds its own
## sprite and collider so the world can spawn it in code.
##
## The origin sits at the character's FEET, which is what lets the world place
## it on a tile top with a plain `y = row * TILE`.
##
## Tuning note: with these numbers a full jump rises ~3.0 tiles and carries
## ~3.7 tiles across. The level generator assumes that — platforms never sit
## more than 2 tiles above the surface you jump from, and pits are 3 wide at
## most, so every orb is reachable without pixel-perfect timing.

const TILE := 48
const RUN_SPEED := 250.0
const ACCEL := 2400.0           # ground responsiveness
const AIR_ACCEL := 1500.0       # weaker in the air, so a jump commits a little
const FRICTION := 2800.0
const GRAVITY := 2150.0
const MAX_FALL := 1250.0
const JUMP_VELOCITY := -790.0
const JUMP_CUT := 0.42          # release early -> shorter hop
const COYOTE_TIME := 0.10       # grace after walking off a ledge
const JUMP_BUFFER := 0.12       # grace when you hit jump just before landing
const RUN_FRAMES := ["player_run_0", "player_run_1", "player_run_2", "player_run_3"]
const RUN_STRIDE := 26.0        # pixels of ground covered per run frame

@warning_ignore("unused_signal")
signal moved()
signal landed()

var input_locked := false

var _sprite: Sprite2D
var _facing := 1
var _coyote := 0.0
var _buffer := 0.0
var _stride := 0.0
var _was_airborne := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 8.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 42)
	shape.shape = rect
	shape.position = Vector2(0, -21)
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = SpriteFactory.texture("player")
	_sprite.scale = Vector2(3, 3)
	_sprite.position = Vector2(0, -24)
	add_child(_sprite)
	z_index = 10


func _physics_process(delta: float) -> void:
	var dir := 0.0
	var jump_pressed := false
	var jump_released := false
	if not input_locked:
		dir = Input.get_axis("move_left", "move_right")
		jump_pressed = Input.is_action_just_pressed("jump")
		jump_released = Input.is_action_just_released("jump")

	var on_floor := is_on_floor()

	# Horizontal: quick to start, with real friction so you can line up a landing.
	var rate := (ACCEL if on_floor else AIR_ACCEL) if not is_zero_approx(dir) else FRICTION
	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, rate * delta)

	if not on_floor:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# Coyote time and jump buffering — the two things that make a jump feel fair
	# rather than punishing. You may jump just after leaving a ledge, and a jump
	# pressed just before you land still fires.
	_coyote = COYOTE_TIME if on_floor else maxf(0.0, _coyote - delta)
	_buffer = JUMP_BUFFER if jump_pressed else maxf(0.0, _buffer - delta)
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
	# Variable height: let go on the way up and the hop is cut short.
	if jump_released and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	move_and_slide()
	_animate(dir, delta)

	if is_on_floor() and _was_airborne:
		landed.emit()
	_was_airborne = not is_on_floor()


func _animate(dir: float, delta: float) -> void:
	if not is_zero_approx(dir):
		_facing = 1 if dir > 0.0 else -1
		_sprite.flip_h = _facing < 0
	_sprite.position.y = -24
	if not is_on_floor():
		# Lean into the arc: stretch rising, squash falling.
		var t := clampf(velocity.y / 700.0, -1.0, 1.0)
		_sprite.scale = Vector2(3.0 - t * 0.2, 3.0 + t * 0.2)
		_sprite.texture = SpriteFactory.texture("player_fall" if velocity.y > 0.0 else "player_jump")
		_stride = 0.0
		return
	_sprite.scale = Vector2(3, 3)
	if absf(velocity.x) < 12.0:
		_stride = 0.0
		_sprite.texture = SpriteFactory.texture("player")
		return
	# Step the run cycle off ground covered rather than off time, so the feet
	# never skate when you are accelerating or shoving into a wall.
	_stride += absf(velocity.x) * delta / RUN_STRIDE
	_sprite.texture = SpriteFactory.texture(RUN_FRAMES[int(_stride) % RUN_FRAMES.size()])


func facing_dir() -> Vector2:
	return Vector2.RIGHT if _facing > 0 else Vector2.LEFT
