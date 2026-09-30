# Adventure mode — Skill Worlds

Adventure mode ("The Ascent to Root") is a top-down 2D game built around one
loop: **learn a skill, then prove it.** You climb the mainframe one WORLD at a
time — and you never "fight," you solve real problems with commands you just
learned.

It reuses the whole engine — the VFS, the shell, and the same
`ConditionEvaluator` the campaign uses — so **every valid solution wins**.

## How it plays

- **Move** with WASD / arrows. **E** acts on a console or portal. **Esc** closes
  a panel, or saves and returns to the menu.
- **Skill orbs** — each world scatters glowing orbs, one per command. Walk into
  one and you learn it: a card shows what the command does and an example, and
  it drops into your kit (the SKILLS row). No fighting, no HP.
- **The trial** — once you've collected a world's orbs, its **trial console**
  unlocks. Press **E** to open a terminal and solve a real problem with exactly
  those skills: make an unrunnable script run (`chmod`), name the intruder
  flooding a log (`grep | sort | uniq -c`), stop the CPU-devouring miner
  (`ps`, `kill`), and so on. Any valid solution passes. On success you get a
  short **"what you learned."**
- **The portal** — passing the trial wakes the portal at the far side of the
  room. Step through it (**E**) to the next world.
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
reaction for the final world). The 2D room for each world is generated in code
from its orb count, so adding a world is pure JSON.

- Logic: `scripts/adventure/` — `AdventureWorld` (parses the worlds),
  `AdventureState` (skills learned, world index, trials passed), and
  `AdventureManager` (orbs, trial gating, solving, advancement).
- Presentation: `scripts/world2d/world2d.gd` builds each world's room, the
  orbs, the trial console and the portal.
- Tested headlessly in `tests/adventure_smoke.gd`, and through the real 2D
  scene in `tests/ui_smoke.gd`.
