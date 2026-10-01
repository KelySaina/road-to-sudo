class_name CharacterSprite
extends Node2D
## A smooth, vector-drawn operator avatar — no pixel art, so it stays crisp at
## any zoom. Draws a stylized top-down "netrunner": dark jacket with neon trim,
## glowing visor, animated walk cycle, facing four directions. Set `facing`,
## `moving` and advance `phase` each frame; call queue_redraw().

var facing := "down"
var moving := false
var phase := 0.0          # walk cycle, radians

# Neon-operator palette (kept in sync with the UI accent).
const SUIT := Color("1b2150")
const SUIT_HI := Color("2a3270")
const SUIT_LO := Color("12153a")
const SKIN := Color("e7b187")
const SKIN_LO := Color("c98f67")
const HAIR := Color("191c38")
const BOOT := Color("0d1030")
const SHADOW := Color(0, 0, 0, 0.26)
var ACCENT := Color("00e5ff")
var ACCENT_SOFT := Color("00e5ff")


func _ready() -> void:
	ACCENT = UiTheme.ACCENT
	ACCENT_SOFT = Color(UiTheme.ACCENT, 0.33)


func _draw() -> void:
	var stride: float = sin(phase) if moving else 0.0
	var swing: float = stride * 3.2
	var bob: float = (-1.5 if (moving and sin(phase) > 0.0) else 0.0)
	# Ground shadow (stays put; the body bobs above it).
	_ellipse(Vector2(0, 21), 12.5, 4.2, SHADOW)
	draw_set_transform(Vector2(0, bob), 0.0, Vector2.ONE)
	match facing:
		"up": _draw_up(swing)
		"left": _draw_side(-1, swing)
		"right": _draw_side(1, swing)
		_: _draw_down(swing)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- facing down (toward the viewer) ----------------------------------------

func _draw_down(swing: float) -> void:
	_leg(Vector2(-4.2, 11), swing, true)
	_leg(Vector2(4.2, 11), -swing, true)
	_torso()
	_arm(Vector2(-10.5, 0), -swing)
	_arm(Vector2(10.5, 0), swing)
	_head(0.0, true)


func _draw_up(swing: float) -> void:
	_leg(Vector2(-4.2, 11), swing, true)
	_leg(Vector2(4.2, 11), -swing, true)
	_torso()
	_arm(Vector2(-10.5, 0), -swing)
	_arm(Vector2(10.5, 0), swing)
	# Back of the head: hood/hair, no face, a thin neon nape line.
	_capsule(Vector2(0, -16), Vector2(0, -10), 9.0, HAIR)
	draw_circle(Vector2(0, -13.5), 8.6, HAIR)
	draw_line(Vector2(-5, -9), Vector2(5, -9), Color(ACCENT, 0.5), 1.4, true)


func _draw_side(sign: int, swing: float) -> void:
	# A 3/4 profile: body slightly turned, one arm leads.
	_leg(Vector2(-1.5, 11), swing, true)
	_leg(Vector2(3.0 * sign, 11), -swing, true)
	_torso()
	_arm(Vector2(-2.0 * sign, 1), swing)          # trailing arm (behind torso)
	_head(float(sign), false)
	_arm(Vector2(9.0 * sign, 1), -swing)          # leading arm (in front)


# --- parts ------------------------------------------------------------------

func _torso() -> void:
	# Jacket: a tapered capsule, darker at the bottom, with a neon seam.
	var pts := PackedVector2Array([
		Vector2(-8.5, -4), Vector2(8.5, -4), Vector2(7, 11), Vector2(-7, 11)])
	draw_colored_polygon(pts, SUIT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7.2, 4), Vector2(7.2, 4), Vector2(7, 11), Vector2(-7, 11)]), SUIT_LO)
	# shoulders
	draw_circle(Vector2(-8, -3.5), 3.6, SUIT_HI)
	draw_circle(Vector2(8, -3.5), 3.6, SUIT_HI)
	# neon seam + collar
	draw_line(Vector2(0, -3), Vector2(0, 10), Color(ACCENT, 0.9), 1.5, true)
	draw_line(Vector2(-6, -3.2), Vector2(6, -3.2), Color(ACCENT, 0.8), 1.6, true)
	# a soft rim glow down one side
	draw_line(Vector2(8, -3), Vector2(6.6, 10.5), ACCENT_SOFT, 2.2, true)


func _head(side: float, front: bool) -> void:
	var cx := 2.6 * side
	var c := Vector2(cx, -13.0)
	# neck
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 3, -6.5), Vector2(cx + 3, -6.5), Vector2(cx + 2.4, -3.2), Vector2(cx - 2.4, -3.2)]), SKIN_LO)
	draw_circle(c, 8.4, SKIN)
	# hair cap
	_arc_cap(c, 8.4, HAIR)
	if front:
		# glowing visor across the eyes + faint outer glow
		draw_line(c + Vector2(-6.4, 1.2), c + Vector2(6.4, 1.2), ACCENT_SOFT, 5.0, true)
		draw_line(c + Vector2(-6.0, 1.2), c + Vector2(6.0, 1.2), ACCENT, 2.6, true)
	else:
		# profile visor on the facing side
		var dirx := 1.0 if side >= 0.0 else -1.0
		draw_line(c + Vector2(1.5 * dirx, 1.0), c + Vector2(6.6 * dirx, 1.0), ACCENT_SOFT, 5.0, true)
		draw_line(c + Vector2(1.8 * dirx, 1.0), c + Vector2(6.2 * dirx, 1.0), ACCENT, 2.6, true)


func _arm(at: Vector2, swing: float) -> void:
	var top := at + Vector2(0, -2)
	var hand := at + Vector2(swing * 0.6, 7.5)
	_capsule(top, hand, 2.8, SUIT)
	draw_circle(hand, 2.3, SKIN)


func _leg(at: Vector2, swing: float, _boot: bool) -> void:
	var hip := at + Vector2(0, -2)
	var foot := at + Vector2(swing, 7.5)
	_capsule(hip, foot, 3.1, SUIT_LO)
	draw_circle(foot + Vector2(0, 0.5), 3.0, BOOT)


# --- primitives -------------------------------------------------------------

func _capsule(a: Vector2, b: Vector2, r: float, color: Color) -> void:
	draw_line(a, b, color, r * 2.0, true)
	draw_circle(a, r, color)
	draw_circle(b, r, color)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 22:
		var a := TAU * i / 22.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


## The top hair cap: the upper ~55% of the head circle.
func _arc_cap(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var a0 := PI * 1.08
	var a1 := TAU + PI * -0.08
	var steps := 16
	for i in range(steps + 1):
		var a: float = a0 + (a1 - a0) * i / steps
		pts.append(c + Vector2(cos(a) * r, sin(a) * r))
	draw_colored_polygon(pts, color)
