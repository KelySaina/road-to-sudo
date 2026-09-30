class_name SpriteFactory
extends RefCounted
## Loads the game's pixel-art tiles (Kenney Tiny Dungeon + Tiny Town, CC0)
## from res://assets/tiles/, cached. Falls back to a tiny procedural tile if a
## texture is missing, so the game still runs without the art.

const DIR := "res://assets/tiles/"
const CELL := 16

static var _cache: Dictionary = {}


static func texture(sprite_name: String) -> Texture2D:
	if _cache.has(sprite_name):
		return _cache[sprite_name]
	var path := DIR + sprite_name + ".png"
	var tex: Texture2D
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		push_warning("Missing tile art: %s (using placeholder)" % path)
		tex = _placeholder(sprite_name)
	_cache[sprite_name] = tex
	return tex


static func has(sprite_name: String) -> bool:
	return ResourceLoader.exists(DIR + sprite_name + ".png")


static func _placeholder(sprite_name: String) -> ImageTexture:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	var tint := Color("5ee6c8") if sprite_name == "floor" else Color("39414f")
	img.fill(tint)
	for i in CELL:
		img.set_pixel(i, 0, Color("0b0d12"))
		img.set_pixel(0, i, Color("0b0d12"))
	return ImageTexture.create_from_image(img)
