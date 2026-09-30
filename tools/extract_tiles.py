#!/usr/bin/env python3
"""Slice the Adventure-mode terrain and hazard tiles out of Buch's CC0 sheet.

Source: "Sci-fi Platformer Tileset" by Michele 'Buch' Bucelli — CC0 1.0
        https://opengameart.org/content/sci-fi-platformer-tileset

The sheet is a 24x24 grid of 16x16 tiles. Only the tiles the game actually
uses are written into assets/tiles/, one PNG per sprite name, which is what
SpriteFactory loads. Re-run after changing the mapping:

    python3 tools/extract_tiles.py

Needs Pillow and network access; the sheet is not bundled.
"""

import io
import pathlib
import sys
import urllib.request

from PIL import Image

SHEET_URL = "https://opengameart.org/sites/default/files/sheet_23.png"
CELL = 16
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "tiles"

# Each colour set is three sheet rows. Within a set the layout is the same, so
# one (column, row-offset) pair names the same tile in every colour.
COLOUR_SETS = {"blue": 0, "red": 3, "green": 6, "orange": 9, "violet": 12}
TERRAIN = {
    "floor": (7, 1),      # solid block with a lit top edge — a standable surface
    "wall": (6, 1),       # plain fill — everything buried under a surface
    "floor_alt": (8, 0),  # lit top with bolts, sprinkled in for variety
    "wall_alt": (8, 1),   # bolted fill, likewise
}

# Hazards are deliberately always the same colour, whatever the world is built
# from, so "this will set you back" never has to be re-learned.
PROPS = {
    "spikes": (0, 15),
    "crate": (5, 15),
    "rover_0": (0, 17), "rover_1": (1, 17), "rover_2": (2, 17), "rover_3": (3, 17),
    "burst_0": (0, 21), "burst_1": (1, 21), "burst_2": (2, 21), "burst_3": (3, 21),
}


def main() -> int:
    print("fetching %s" % SHEET_URL)
    with urllib.request.urlopen(SHEET_URL, timeout=60) as r:
        sheet = Image.open(io.BytesIO(r.read())).convert("RGBA")
    if sheet.size != (384, 384):
        print("unexpected sheet size %s — mapping may be stale" % (sheet.size,))
        return 1
    OUT.mkdir(parents=True, exist_ok=True)

    written = []
    for colour, base in COLOUR_SETS.items():
        for name, (tx, dy) in TERRAIN.items():
            _cut(sheet, tx, base + dy, "%s_%s" % (colour, name), written)
    for name, (tx, ty) in PROPS.items():
        _cut(sheet, tx, ty, name, written)

    print("wrote %d tiles to %s" % (len(written), OUT))
    return 0


def _cut(sheet: Image.Image, tx: int, ty: int, name: str, written: list) -> None:
    tile = sheet.crop((tx * CELL, ty * CELL, tx * CELL + CELL, ty * CELL + CELL))
    tile.save(OUT / ("%s.png" % name))
    written.append(name)


if __name__ == "__main__":
    sys.exit(main())
