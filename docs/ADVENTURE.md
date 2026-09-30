# Adventure mode — Skill Worlds

Adventure mode ("The Ascent to Root") is a side-scrolling 2D **platformer**
built around one loop: **learn a skill, then prove it.** You run and jump your
way up the mainframe one WORLD at a time — and you never "fight," you solve real
problems with commands you just learned.

It reuses the whole engine — the VFS, the shell, and the same
`ConditionEvaluator` the campaign uses — so **every valid solution wins**.

## How it plays

- **Run** with `A`/`D` or ← →, **jump** with `Space` or `W`. **E** acts on a
  console or portal. **Esc** closes a panel, or saves and returns to the menu.
- **The course** — each world is one side-scrolling level: solid ground broken by
  pits, with ledges you reach in a single jump. There is no HP and nothing can
  kill you; fall in a pit and you're simply set back down on the last ground you
  stood on.
- **Skill orbs** — orbs sit on the ledges, one per command, so every skill costs
  you a jump. Reach one and you learn it: a card shows what the command does, it
  drops into your kit (the SKILLS row) — and then it hands you a **practice
  prompt**.
- **Practice** — a real terminal on the real machine, opened the moment you take
  an orb. The world's trial files are laid out first so the example actually
  runs, and **nothing here is graded**: run the example, run something else, look
  around. Use the command in any form and it's acknowledged; `Esc` returns you to
  the course. It is the difference between reading `chmod +x` and typing it.
- **The trial** — once you've collected a world's orbs, its **trial console**
  unlocks. Press **E** to open a terminal and solve a real problem with exactly
  those skills: make an unrunnable script run (`chmod`), name the intruder
  flooding a log (`grep | sort | uniq -c`), stop the CPU-devouring miner
  (`ps`, `kill`), and so on. Any valid solution passes. On success you get a
  short **"what you learned."**
- **The portal** — passing the trial wakes the portal at the end of the course.
  Step through it (**E**) to the next world.
- **`talk <command>`** — inside a trial you can ask for any command in plain
  words: `talk grep`, `talk find`, `talk sudo`. `hint` gives graded help.
- **Nudges** — use the wrong tool (reading 4,000 log lines with `cat`, hunting a
  process with `ls`) and the game nudges you toward the right one, once.

## The worlds

1. **The Filesystem** — `ls`, `cat`, `chmod` → make a keycard script run.
2. **The Log Swamp** — `grep`, `sort`, `uniq` → name the intruder in `auth.log`.
3. **The Process Foundry** — `ps`, `top`, `kill` → stop the miner, spare the
   backup daemon.
4. **The Tangled Archive** — `find`, `mkdir`, `cp` → recover a buried config.
5. **The Cutting Room** — `cut`, `sort`, `uniq` → name the most frequent account.
6. **The Throne of root** — `id`, `sudo`, `rm` → collecting the **sudo orb**
   earns you the right; become root, remove the impostor's launcher, and end it.
   Passing this trial wins the Ascent: *"YOU MADE IT."*

XP from trials feeds the same rank ladder as the campaign, and the run is saved.

## The data

Everything lives in `data/adventure/worlds.json`: an ordered list of worlds,
each with `orbs` (skill + `teaches` + `example`, and an optional `grant_group`)
and a `trial` (`objective`, `setup`, `success`, `hints`, `learned`, and
`reactions` — the same shapes challenges use, plus an optional `respawn` on a
reaction for the final world). Each orb's `example` must be a command that
actually runs against the world's trial `setup`, since the practice prompt
invites the player to type it. The course for each world is generated in code
from its orb count, so adding a world is pure JSON.

- Logic: `scripts/adventure/` — `AdventureWorld` (parses the worlds),
  `AdventureState` (skills learned, world index, trials passed), and
  `AdventureManager` (orbs, trial gating, solving, advancement).
- Presentation: `scripts/world2d/world2d.gd` plans and builds each world's
  course (ground, pits, ledges), the orbs, the practice prompt, the trial console
  and the portal. `scripts/world2d/player.gd` is the platformer controller —
  gravity, coyote time, jump buffering and variable jump height. Its tuning and
  the level generator agree on one contract: a full jump clears ~3 tiles of
  height and ~3.7 across, so ledges sit 2 tiles up and pits are at most 3 wide.
- Art: `scripts/world2d/sprite_factory.gd` — the tiles, console, portal and
  operator are 16x16 colour maps authored in place, in the UiTheme palette.
- Tested headlessly in `tests/adventure_smoke.gd`, and through the real 2D
  scene in `tests/ui_smoke.gd` — which also holds the generator to its contract:
  every orb sits on a ledge, every ledge is within one measured jump of a lower
  surface, and no pit is wider than a jump.
