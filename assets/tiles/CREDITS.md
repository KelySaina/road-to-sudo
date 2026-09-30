# Art credits

**Terrain and hazards — "Sci-fi Platformer Tileset" by Michele 'Buch' Bucelli**,
released under **CC0 1.0** (public domain — no attribution required, but very
much appreciated).

  https://opengameart.org/content/sci-fi-platformer-tileset

The sheet itself is not bundled. `tools/extract_tiles.py` fetches it and slices
out only the tiles the game uses, one PNG per sprite name:

- `<colour>_floor` / `_floor_alt` — a block with a lit top edge: a surface you
  can stand on. `<colour>_wall` / `_wall_alt` — everything buried beneath one.
  Five colours (blue, red, green, orange, violet); each world picks one with a
  `"palette"` in `data/adventure/worlds.json`.
- `spikes`, `rover_0..3`, `burst_0..3` — the three hazards, always in the same
  colour whatever the world is built from, so "this will set you back" never has
  to be re-learned.
- `crate` — the lift platform.

**The console, the portal and the operator are original**, authored as 16x16
colour maps in `scripts/world2d/sprite_factory.gd` so they sit in the game's own
palette. A PNG dropped in here under one of those names overrides the built-in
map; anything else with no PNG and no built-in map falls back to a placeholder.

The earlier top-down build used Kenney's *Tiny Dungeon* / *Tiny Town* tiles
(also CC0). Nothing loads them any more, so they were removed — `git log` has
them if they are ever wanted back.
