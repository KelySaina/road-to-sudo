# Adventure mode — the 2D RPG

Adventure mode ("The Ascent to Root") is a real top-down 2D game. You steer an
operator around the mainframe's rooms; walking up to a console and pressing E
opens a terminal where you fight with real Linux commands. The world is a
wounded server and you climb from a powerless user to root.

It reuses the whole engine — the VFS, the shell, and the same
`ConditionEvaluator` the campaign uses — so **every valid solution wins**.
Nothing is a separate combat minigame: you fight by typing real commands.

## How it plays

- **Move** with WASD / arrows. **E** interacts with whatever you're standing
  next to. **Esc** closes a panel, or saves and returns to the menu.
- **NPCs** (Tux the old daemon, the Archivist, the Gatekeeper of sudo) open a
  dialogue box with story and hints. The Gatekeeper grants you `sudo` once you
  hold the three keys.
- **Consoles / monsters** open a **terminal overlay**. That console's fight is
  a Linux problem: make an unrunnable script run (`chmod`), name the intruder
  flooding a log (`grep`), kill the CPU-devouring miner without killing the
  honest daemon (`ps`, `kill`). Solve it and the console clears, a key drops,
  and a door opens.
- **HP**: reckless actions (a `trap` — killing the wrong process, deleting the
  wrong file) cost health. At 0 HP the machine "reboots": you respawn at the
  same spot with full health and the fight reset — a gentle checkpoint.
- **Doors** gate the rooms; each opens when its room is cleared (or, for the
  throne, when you hold `sudo`).
- **Learning the commands**: type `learn` at any prompt for a categorized cheat
  sheet (what each command does, with an example), or `learn <command>` /
  `man <command>` for one. Every fight ends with a short "what you learned"
  note naming the commands you just used.

The vertical slice, **The Ascent to Root**, is eight rooms:

1. **The Waking Terminal** — Tux explains the controls.
2. **The Rusted Gate** — an unrunnable keycard script (`chmod`, `./`).
3. **The Log Swamp** — the Archivist; name the intruder in `auth.log`.
4. **The Process Foundry** — kill the rogue miner, spare the backup daemon.
5. **The Tangled Archive** — find a file buried under `/etc` and copy it out
   (`find`, `cp`, `mkdir`).
6. **The Cutting Room** — rank a CSV to name the worst offender
   (`cut`, `sort`, `uniq`, pipes).
7. **The Gate of sudo** — the Gatekeeper grants you sudo.
8. **The Core** — the boss `initd-imposter`, which respawns from its launcher.
   Become root, destroy the launcher, end the process, hold the throne.

Pixel art is by **Kenney** (Tiny Dungeon + Tiny Town, CC0); see
`assets/tiles/CREDITS.md`. Swap in your own 16×16 PNGs with the same names to
reskin it.

## Architecture
Adventure mode is a thin layer on the existing engine.

```text
 terminal ─▶ Game.submit ─▶ Shell (real Linux commands + adventure verbs)
                              │  verbs emit events: adv_move, adv_look,
                              │  adv_talk, adv_hint
                              ▼
                        ExecutionOutcome
                              │
              Game.submit ─▶ AdventureManager.observe(outcome)
                              │  · handles the verb events (move/look/talk)
                              │  · checks traps  → damage / respawn / reboot
                              │  · checks the node's success condition → win
                              ▼
                     signals: narrate, state_changed, battle_won,
                     player_damaged, adventure_won  → EventBus → UI
```

- **`scripts/adventure/adventure_world.gd`** loads `data/adventure/world.json`
  (nodes kept as raw dicts).
- **`scripts/adventure/adventure_state.gd`** is the saved progress: HP,
  current node, cleared nodes, flags/keys, deaths.
- **`scripts/adventure/adventure_manager.gd`** is the runtime. It reuses
  `ConditionEvaluator` for battle success and traps, and
  `MachineBuilder.apply_files` for per-node setup — the exact same code the
  campaign challenges use.
- The verbs are ordinary `BaseCommand`s in `scripts/commands/adv_*.gd`; they
  read `ShellSession.adventure` and emit events. `AdventureManager.observe`
  does the work, so narration types out *after* the command's echo.
- **`scripts/ui/adventure_panel.gd`** is the side panel (location, HP bar,
  objective, exits, keys). It reads `Game.adventure` and reacts to the
  EventBus.

Save/load uses a dedicated `"adventure"` world slot that stores the machine
plus the `AdventureState`, so *Continue* resumes mid-journey with your HP,
keys and world changes intact.

## Adding to the world

Everything is data in `data/adventure/world.json`. A node:

```json
"foundry": {
  "id": "foundry", "name": "The Process Foundry", "type": "battle",
  "cwd": "~",
  "on_enter": ["story lines shown on first arrival"],
  "on_return": ["shorter lines shown on later visits"],
  "art": ["optional ascii lines"],
  "enemy": {"name": "The Miner", "taunt": ["shown when the fight begins"]},
  "npc": {"name": "...", "lines": ["talk dialogue"], "hint": "talk hint"},
  "battle": {
    "objective": "what the player must achieve (never the command)",
    "hints": ["vague", "concept", "nearly the command"],
    "setup": { "files": {...}, "processes": [...], "remove": [...] },
    "traps": [
      {"when": <condition>, "damage": 7, "say": "...", "once": true,
       "respawn": { "pid": 1313, "user": "root", "cmd": "..." }}
    ],
    "success": <condition>,
    "reward_flags": ["cpu_freed"], "reward_xp": 110,
    "grant_group": "sudo",
    "victory": ["shown on victory"]
  },
  "on_enter_grant": {"needs": ["a","b"], "flags": ["c"], "grant_group": "sudo", "say": [...]},
  "locks": {"north": {"needs": ["sudo_access"], "blocked": ["message"]}},
  "exits": {"north": "gatekeeper", "south": "swamp"}
}
```

- `setup`, `success` and `traps` use exactly the same schema as challenges —
  see [ADDING_CHALLENGES.md](ADDING_CHALLENGES.md) for the condition types.
  Adventure adds one condition: `{"type": "has_flag", "flag": "keycard"}`.
- A `battle`/`boss` node blocks its exits until it's cleared (so you can't
  flee a fight). Set `"open_exits_in_battle": true` to allow leaving.
- `traps` may carry `"respawn"` (a process to re-add) for boss mechanics.
- `on_enter_grant` is a story gate that hands out flags/`grant_group` the
  first time the player arrives with the required keys (the Gatekeeper).
- `locks` bar an exit until the player holds the listed flags.
- `win: true` on a node ends the adventure when it's cleared.

Test additions by extending `tests/adventure_smoke.gd`, which plays the whole
region (and the traps, the reboot and the boss) headlessly. Design rules are
the same as challenges: **describe the problem, not the command**, accept
every valid solution, and make mistakes memorable but recoverable.

## The 2D layer

The RPG *logic* lives in `scripts/adventure/` (state, world, manager) and is
UI-agnostic — it's what the headless `tests/adventure_smoke.gd` drives. The 2D
*presentation* lives in `scripts/world2d/`:

- **`sprite_factory.gd`** loads the Kenney tiles from `assets/tiles/` by name.
- **`player.gd`** — the `CharacterBody2D` you steer, with collision.
- **`interactable.gd`** — a console / NPC / boss you can stand next to; shows
  its `[E]` prompt.
- **`blocker.gd`** — a door that opens when its condition is met.
- **`world2d.gd`** — builds the map from `data/adventure/map.json`, spawns the
  player, camera, HUD and the terminal overlay, and reacts to the manager's
  signals (`battle_won` clears a console and opens doors; `adventure_won`
  shows the victory screen).

The manager exposes a 2D-facing API alongside the text one: `prepare()` (set
up without narrating), `engage(node)` (start a console's fight), `visit_npc()`
(dialogue + story grants) and `disengage()`. Walking replaces the `go` verb;
`observe()` still checks traps and success while a console is open.

`Game.start_adventure2d()` boots the `mainframe` machine, prepares the
manager, and Main swaps in `world2d.tscn`. Save/load uses the `"adventure"`
world slot (machine + `AdventureState`), so *Continue* resumes where you were.

## Editing the map

`data/adventure/map.json` is the room layout, regenerated by the small script
in the project history but easy to hand-edit:

- `rows`: an ASCII grid, `#` = wall, `.` = floor. `tile` is the pixel size.
- `spawn`: `[x, y]` tile coordinates for the player start.
- `objects`: `{kind: "npc"|"console"|"boss", node: "<world node id>",
  at: [x, y], sprite: "<tile name>", label: "...", enemy: true?}` — each maps a
  physical object to a node in `world.json`.
- `doors`: `{tiles: [[x,y]...], needs_cleared: "<node>" | needs_flag: "<flag>"
  | open: true, ...}` — a blocker that opens on that condition.

Sprite names must exist in `assets/tiles/` (or add a new PNG there). The story,
fights, hints and rewards all stay in `world.json` — see the field reference
above; the map only decides where things physically are.
