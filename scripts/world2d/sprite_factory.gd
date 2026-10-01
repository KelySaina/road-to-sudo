class_name SpriteFactory
extends RefCounted
## The game's pixel art, authored in place as 16x16 colour maps.
##
## Terrain and hazards are PNGs sliced from a CC0 sheet (tools/extract_tiles.py)
## and the operator is vector-drawn (CharacterSprite); what is authored here is
## the props with no equivalent in either — the CRT workstation and the portal.
## Keeping those pixels here rather than in PNGs means they are written in the
## same palette as the rest of the UI (see UiTheme) and edit in a text diff.
##
## A PNG in res://assets/tiles/<name>.png still wins for any name that has no
## built-in map, so custom art can be dropped in without touching code.

const DIR := "res://assets/tiles/"
const CELL := 16

static var _cache: Dictionary = {}

## char -> hex colour, plus the 16 rows. "." is transparent.
const ART := {
	# Terrain now comes from Buch's CC0 sheet (see tools/extract_tiles.py), one
	# PNG per colour per role. What stays here is the art with no equivalent in
	# that sheet: the console, the portal and the operator.
	# The trial console: a CRT workstation with a live prompt on it.
	"console": {
		"outline": "05030f",
		"palette": {
			"F": "241d55", "G": "15103a", "s": "07131f", "t": "0c3a4a",
			"T": "00e5ff", "B": "0c0826",
		},
		"rows": [
			"................",
			"..FFFFFFFFFFFF..",
			".FGGGGGGGGGGGGF.",
			".FGssssssssssGF.",
			".FGsTTtttttssGF.",
			".FGssssttttssGF.",
			".FGsTTTtttttsGF.",
			".FGssssssssssGF.",
			".FGGGGGGGGGGGGF.",
			"..FFFFFFFFFFFF..",
			"....FF....FF....",
			"....FF....FF....",
			"...FFFFFFFFFF...",
			"..FFFFFFFFFFFF..",
			".FFFFFFFFFFFFFF.",
			".BBBBBBBBBBBBBB.",
		],
	},
	# Same machine, trial passed: the screen goes green.
	"console_done": {
		"outline": "05030f",
		"palette": {
			"F": "241d55", "G": "15103a", "s": "07131f", "t": "0f4436",
			"T": "2bffb0", "B": "0c0826",
		},
		"rows": [
			"................",
			"..FFFFFFFFFFFF..",
			".FGGGGGGGGGGGGF.",
			".FGssssssssssGF.",
			".FGsTTtttttssGF.",
			".FGsssstttsssGF.",
			".FGsTTTtttttsGF.",
			".FGssssssssssGF.",
			".FGGGGGGGGGGGGF.",
			"..FFFFFFFFFFFF..",
			"....FF....FF....",
			"....FF....FF....",
			"...FFFFFFFFFF...",
			"..FFFFFFFFFFFF..",
			".FFFFFFFFFFFFFF.",
			".BBBBBBBBBBBBBB.",
		],
	},
	# The portal to the next world.
	"door": {
		"outline": "05030f",
		"palette": {
			"R": "3a2a6e", "l": "5b3fa8", "n": "8a5bd6", "w": "c15bff", "r": "2a1e52",
		},
		"rows": [
			"................",
			"....RRRRRRRR....",
			"..RRllllllllRR..",
			".RRllnnnnnnllRR.",
			".RlnnnnnnnnnnlR.",
			".Rlnnwwwwwwnnlr.",
			".Rlnwwwwwwwwnlr.",
			".Rlnwwwwwwwwnlr.",
			".Rlnwwwwwwwwnlr.",
			".Rlnnwwwwwwnnlr.",
			".RlnnnnnnnnnnlR.",
			".RRllnnnnnnllRR.",
			"..RRllllllllRR..",
			"...RRRRRRRRRR...",
			"...RR......RR...",
			"..RRR......RRR..",
		],
	},
}


static func texture(sprite_name: String) -> Texture2D:
	if _cache.has(sprite_name):
		return _cache[sprite_name]
	var tex: Texture2D
	if ART.has(sprite_name):
		tex = _from_art(ART[sprite_name])
	else:
		var path := DIR + sprite_name + ".png"
		if ResourceLoader.exists(path):
			tex = load(path)
		else:
			push_warning("No art for sprite: %s (using placeholder)" % sprite_name)
			tex = _placeholder(sprite_name)
	_cache[sprite_name] = tex
	return tex


## A soft radial glow in `tint`, cached per colour. Used for the skill orbs and
## for the halo that keeps a hazard readable against any world's palette.
static func glow(tint: Color, size: int = 16) -> ImageTexture:
	var key := "glow:%s:%d" % [tint.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size / 2.0 - 0.5, size / 2.0 - 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre) / (size / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a * a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func has(sprite_name: String) -> bool:
	return ART.has(sprite_name) or ResourceLoader.exists(DIR + sprite_name + ".png")


static func _from_art(art: Dictionary) -> ImageTexture:
	var rows: Array = art.rows
	var palette: Dictionary = art.palette
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var solid: Dictionary = {}
	for y in mini(CELL, rows.size()):
		var row: String = rows[y]
		for x in mini(CELL, row.length()):
			var key := row[x]
			if not palette.has(key):
				continue
			img.set_pixel(x, y, Color(palette[key]))
			solid[Vector2i(x, y)] = true
	# Trace a 1px outline round the silhouette from the shape itself, rather
	# than drawing it by hand in every frame. It is what keeps a sprite legible
	# against five different world palettes.
	if art.has("outline"):
		var ink := Color(art.outline)
		for y in CELL:
			for x in CELL:
				if solid.has(Vector2i(x, y)):
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if solid.has(Vector2i(x, y) + d):
						img.set_pixel(x, y, ink)
						break
	return ImageTexture.create_from_image(img)


static func _placeholder(sprite_name: String) -> ImageTexture:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	var tint := Color("5ee6c8") if sprite_name == "floor" else Color("39414f")
	img.fill(tint)
	for i in CELL:
		img.set_pixel(i, 0, Color("0b0d12"))
		img.set_pixel(0, i, Color("0b0d12"))
	return ImageTexture.create_from_image(img)
