class_name SpriteFactory
extends RefCounted
## The game's pixel art, authored in place as 16x16 colour maps.
##
## Adventure mode is set inside a failing mainframe, so the art is machine, not
## masonry: deck plating with a lit edge, circuit substrate underneath, a CRT
## workstation and a portal. Keeping the pixels here rather than in PNGs means
## they are written in the same palette as the rest of the UI (see UiTheme) and
## can be edited in a text diff.
##
## A PNG in res://assets/tiles/<name>.png still wins for any name that has no
## built-in map, so custom art can be dropped in without touching code.

const DIR := "res://assets/tiles/"
const CELL := 16

static var _cache: Dictionary = {}

## char -> hex colour, plus the 16 rows. "." is transparent.
const ART := {
	# Deck plating: the top surface of the ground and of every ledge. The lit
	# cyan edge is what makes a platform read as standable at a glance.
	"floor": {
		"palette": {
			"A": "3de8ff", "a": "1a7f94", "H": "2a2260", "P": "1e1850",
			"s": "0c0926", "o": "3b3184", "M": "191342", "D": "151038", "K": "0f0b28",
		},
		"rows": [
			"AAAAAAAAAAAAAAAA",
			"aaaaaaaaaaaaaaaa",
			"HHHHHHHsHHHHHHHs",
			"PPPPPPPsPPPPPPPs",
			"PPPPPPPsPPPPPPPs",
			"PPoPPPPsPPPoPPPs",
			"PPPPPPPsPPPPPPPs",
			"PPPPPPPsPPPPPPPs",
			"MMMMMMMsMMMMMMMs",
			"DDDDDDDsDDDDDDDs",
			"DDDDDDDsDDDDDDDs",
			"DDoDDDDsDDDoDDDs",
			"DDDDDDDsDDDDDDDs",
			"DDDDDDDsDDDDDDDs",
			"KKKKKKKsKKKKKKKs",
			"KKKKKKKKKKKKKKKK",
		],
	},
	# The same plate with a status LED, sprinkled about so long runs of ground
	# don't read as one flat smear.
	"floor_alt": {
		"palette": {
			"A": "3de8ff", "a": "1a7f94", "H": "2a2260", "P": "1e1850",
			"s": "0c0926", "o": "3b3184", "M": "191342", "D": "151038", "K": "0f0b28",
			"L": "2bffb0", "V": "c15bff",
		},
		"rows": [
			"AAAAAAAAAAAAAAAA",
			"aaaaaaaaaaaaaaaa",
			"HHHHHHHsHHHHHHHs",
			"PPPPPPPsPPPPPPPs",
			"PPPPPPPsPPPPPPPs",
			"PPLPPPPsPPPoPPPs",
			"PPPPPPPsPPPPPPPs",
			"PPPPPPPsPPPPPPPs",
			"MMMMMMMsMMMMMMMs",
			"DDDDDDDsDDDDDDDs",
			"DDDDDDDsDDDDDDDs",
			"DDoDDDDsDDDVDDDs",
			"DDDDDDDsDDDDDDDs",
			"DDDDDDDsDDDDDDDs",
			"KKKKKKKsKKKKKKKs",
			"KKKKKKKKKKKKKKKK",
		],
	},
	# Substrate: everything buried under a surface, and the sealed ends of a
	# course. Faint traces so it reads as the inside of a machine, dark enough
	# that the player and the orbs stay the brightest things on screen.
	"wall": {
		"palette": {"u": "0f0b26", "S": "0a061c", "v": "10182f", "n": "16283c"},
		"rows": [
			"uuuuuuuuuuuuuuuu",
			"SSSSSSSSSSSSSSSS",
			"SSSSSSSSvSSSSSSS",
			"SSSSSSSSvvvvSSSS",
			"SSSSSSSSSSSvSSSS",
			"SvvvvSSSSSSvSSSS",
			"SvSSSSSSSSSnSSSS",
			"SvSSSSSSSSSSSSSS",
			"SnSSSSSSSSSSSSSS",
			"SSSSSSSSSSSSSSSS",
			"SSSSSSSSSvvvvSSS",
			"SSSSSSSSSvSSSSSS",
			"SSSSSSSSSnSSSSSS",
			"SSSSSSSSSSSSSSSS",
			"SSSSSSSSSSSSSSSS",
			"uuuuuuuuuuuuuuuu",
		],
	},
	# A second substrate tile, scattered through the first so a big block of
	# machine doesn't read as one stamped-out pattern.
	"wall_alt": {
		"palette": {"u": "0f0b26", "S": "0a061c", "v": "10182f", "n": "16283c"},
		"rows": [
			"uuuuuuuuuuuuuuuu",
			"SSSSSSSSSSSSSSSS",
			"SSSvvvvSSSSSSSSS",
			"SSSvSSSSSSSSSSSS",
			"SSSvSSSSSSvvvSSS",
			"SSSnSSSSSSvSSSSS",
			"SSSSSSSSSSvSSSSS",
			"SSSSSSSSSSnSSSSS",
			"SSSSSSSSSSSSSSSS",
			"SSvSSSSSSSSSSSSS",
			"SSvvvvvSSSSSSSSS",
			"SSSSSSvSSSSSSSSS",
			"SSSSSSnSSSSSSSSS",
			"SSSSSSSSSSSSSSSS",
			"SSSSSSSSSSSSSSSS",
			"uuuuuuuuuuuuuuuu",
		],
	},
	# The trial console: a CRT workstation with a live prompt on it.
	"console": {
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
	# The operator: visor, ops suit, mag boots. Drawn facing right, feet on the
	# bottom row so Player2D's feet-origin lands flush on a tile top.
	"player": {
		"palette": {
			"h": "2a2456", "H": "3a3270", "v": "00e5ff", "V": "8ff6ff",
			"b": "232050", "B": "2e2a63", "C": "2bffb0", "L": "15113a", "k": "0d0a24",
		},
		"rows": [
			"................",
			".....hhhhhh.....",
			"....hhhhhhhh....",
			"....hvvvvvVh....",
			"....hvvvvvVh....",
			"....hhhhhhhh....",
			"...HHbbbbbbHH...",
			"...HHbbbbbbHH...",
			"...HHbbCbbbHH...",
			"....bbbbbbbb....",
			"....bBbbbbBb....",
			"....bbbbbbbb....",
			".....bb..bb.....",
			".....bb..bb.....",
			"....LLLL.LLLL...",
			"....kkkk.kkkk...",
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


static func has(sprite_name: String) -> bool:
	return ART.has(sprite_name) or ResourceLoader.exists(DIR + sprite_name + ".png")


static func _from_art(art: Dictionary) -> ImageTexture:
	var rows: Array = art.rows
	var palette: Dictionary = art.palette
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in mini(CELL, rows.size()):
		var row: String = rows[y]
		for x in mini(CELL, row.length()):
			var key := row[x]
			if not palette.has(key):
				continue
			img.set_pixel(x, y, Color(palette[key]))
	return ImageTexture.create_from_image(img)


static func _placeholder(sprite_name: String) -> ImageTexture:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	var tint := Color("5ee6c8") if sprite_name == "floor" else Color("39414f")
	img.fill(tint)
	for i in CELL:
		img.set_pixel(i, 0, Color("0b0d12"))
		img.set_pixel(0, i, Color("0b0d12"))
	return ImageTexture.create_from_image(img)
