# Road to sudo

**Learn Linux by using it.** A terminal RPG in Godot 4 where you start as a
complete beginner at a `$` prompt and work your way to `root@server:~#`.

No quizzes and no "type `chmod +x` now" tutorials. You get a simulated
machine, a problem, and a shell. You investigate, form a hypothesis, change
something and check the result. The game checks the **resulting state of the
machine**, not the keystrokes, so any valid solution passes.

```text
player@workstation:~$ ./backup.sh
bash: ./backup.sh: Permission denied
player@workstation:~$ ls -l backup.sh
-rw-r--r-- 1 player player 276 Jun  5 09:14 backup.sh
player@workstation:~$ chmod u+x backup.sh && ./backup.sh
Backing up /home/player/projects...

  ✔ OBJECTIVE COMPLETE — Permission denied
    +150 XP   +50 no-hint bonus
```

This is an early build with a lot in it: a full **8-level campaign (40
challenges)** that takes you from `whoami` to taking **root on a burning
production server**, plus a **2D RPG adventure mode**. A few advanced topics
(networking, services, packages, SSH, git) are the next waves.

---

## Running it

**Requirements:** Godot **4.4 or newer** (developed and tested with 4.4.1
stable). It uses the GL Compatibility renderer, so it runs on modest GPUs.

- **Editor:** open Godot, choose *Import*, select `road-to-sudo/project.godot`,
  then press **F5**.
- **Command line:** `godot --path road-to-sudo`

On a fresh checkout Godot imports the project on first open, which builds
its class cache. If you only use the CLI, run
`godot --headless --path . --import` once.

### Tests

```bash
GODOT=/path/to/godot tools/run_tests.sh
```

This runs:

- `tests/run_tests.gd`: 231 assertions over the VFS, permissions, parser,
  every command, progression and achievements. It plays **every challenge's
  solution plus alternative solutions**, and checks that wrong answers and
  half-fixes do not pass.
- `tests/adventure_smoke.gd`: plays the whole RPG region end to end — every
  fight, the damage traps, the respawning boss and the death/reboot — 38
  assertions.
- `tests/ui_smoke.tscn`: boots the real main scene with its autoloads. It
  plays the whole campaign through the terminal widget, sends real key
  events (typing, Tab, ↑, Enter, F1), and covers Expert mode with
  skip-basics, `:skip`, save → continue mid-challenge, and `:reset`. It uses
  a separate save file, so your real progress is untouched.

Dev helpers (they need a display, not `--headless`):

- `tests/screenshots.tscn -- <dir>` and `tests/world_shots.tscn -- <dir>`
  render the campaign and 2D-world screens to PNG.
- `tests/transcript.gd` prints a command transcript so you can check
  output formatting.

## Controls

| Key | Action |
|---|---|
| `Enter` | run the command, or continue after an objective |
| `Tab` | complete a command, path or `:meta` command; ambiguous matches are listed |
| `↑` / `↓` | move through history |
| `Ctrl+L` | clear the screen (same as `clear`) |
| `Ctrl+C` / `Ctrl+U` | cancel the line / delete to the start of the line |
| `Ctrl+A` / `Ctrl+E` | move to the start / end of the line |
| `PgUp` / `PgDn` | scroll the output |
| `F1` | next hint (same as `:hint`) |
| `Esc` | back (menus) |

Typing anywhere on the game screen goes to the prompt. Menus work entirely
from the keyboard.

**Game commands** start with `:`. They are kept apart from Linux on purpose,
so the Linux layer stays honest: `:hint`, `:solution`, `:objective`,
`:reset`, `:skip`, `:next`, `:stats`, `:save`, `:menu`.

## What's in the slice

- **Main menu:** Start Journey (Beginner / Normal / Expert, plus "skip the
  basics"), Continue, **Adventure**, Practice Lab, Achievements, Settings and
  Exit.
  Starting over and resetting progress each ask for confirmation first.
- **Campaign — 8 levels, 40 challenges** (state-checked, so any valid solution
  passes), ending by taking root on a production server:
- **Level 0 · First Contact**, 10 challenges:
  1. *Who are you?* (`whoami` / `id`)
  2. *Where are you?* (`pwd`)
  3. *Look around* (`ls`, `cat`)
  4. *Nothing to see here* (hidden files, `ls -a`, `man`)
  5. *Where the logs live* (`cd`, the filesystem layout)
  6. *Make yourself at home* (`mkdir`, `touch`, relative paths)
  7. *Leave a note* (`echo`, `>` / `>>`)
  8. *Needle, meet haystack*: a 3,000-line `auth.log`, find the targeted
     account (`grep`, pipes, `sort | uniq -c | sort -rn`)
  9. *Permission denied*: Alice's backup script (`ls -l`, `chmod`)
  10. *Your first incident*: a report generator fails for two independent
      reasons. You have to read the logs and fix both.
- **Level 1 · The Filesystem**, 6 challenges: `cp`, `mv`, `rm -r`, globs, `find`.
- **Level 2 · Text & Pipes**, 5: `grep`, `cut`, `sort | uniq -c | sort -rn`,
  `wc`, and tracing an attacker's IP through 3,000 log lines.
- **Level 3 · Permissions**, 5: lock secrets to 600, `chmod 750`, close a
  world-writable hole, set a private `umask`, fix a "Permission denied" script.
- **Level 4 · Users & Groups**, 4: `id`, reading `/etc/passwd` and `/etc/group`,
  and finding who holds `sudo`.
- **Level 5 · Processes**, 5: `ps`/`top`, `kill`, `pkill`, `kill -9`, and
  clearing a multi-process outbreak.
- **Level 6 · Logs & Debugging**, 4: read the last error, count errors, spot a
  break-in in `auth.log`, and follow a log to the fix.
- **Final · Road to sudo**: a broken production server, no hand-holding —
  investigate, `sudo -i`, stop the rogue root process, and hold the throne.
- **Adventure mode — "The Ascent to Root" (a 2D RPG):** a real top-down game.
  You steer an operator (WASD / arrows) through the mainframe's rooms, walk up
  to consoles, NPCs and monsters, and press **E**. Consoles open a **terminal
  overlay** where you fight with real Linux commands; NPCs (Tux the old daemon,
  the Archivist, the Gatekeeper of sudo) give story and hints; locked **doors**
  open as you clear each room. You have **HP** — reckless commands (killing the
  wrong process, deleting the wrong file) cost health, and at 0 the machine
  reboots you to a checkpoint. It ends with a boss, `initd-imposter`, a daemon
  wearing root's face that respawns from its launcher until you destroy it and
  claim the throne with `sudo -i`. Six rooms, keys, and XP that feeds the same
  ranks. Every fight ends with a short "what you learned" note, and `learn`
  opens a cheat sheet at any prompt. Pixel art by Kenney (CC0). Full write-up:
  [docs/ADVENTURE.md](docs/ADVENTURE.md).
- **Practice Lab:** a separate sandbox machine with no objectives and no
  score.
- **60 simulated commands:**
  - basics: `pwd cd ls echo clear help man history learn`  (`learn` is a
    friendly cheat sheet of what every command does, with examples)
  - files: `cat less touch mkdir rmdir rm cp mv find tree stat file`
  - text: `grep head tail wc sort uniq cut tr`
  - permissions: `chmod chown/chgrp umask`
  - users: `whoami id groups who su sudo`
  - processes: `ps top kill pkill pgrep`
  - system: `hostname uname date`
  - shell: `bash/sh env/printenv export unset which exit true false`
- **Shell features:** pipes, `>`, `>>`, `<`, `2>`, `2>&1`, `>&2`, `&&`,
  `||`, `;`, quoting, `$VAR` / `${VAR}` / `$?`, `~` expansion, `*` / `?`
  globs, `NAME=value`, and scripts with `$1..$9` and `exit N`. Running a
  script checks real permissions: `./x.sh` needs `x`, `bash x.sh` only
  needs `r`.
- **Learning system:** three progressive hints per challenge, then the
  solution. Challenges react to what the player does (for example the
  `bash backup.sh` loophole or reading a log). Beginner mode gets
  explanations after each objective and inline command help under the
  prompt. Expert mode gets vaguer objectives, one hint, no solution and a
  speed bonus.
- **Failure teaches:** delete a protected file and the game stops you with
  *"Wait. Was that intentional?"*, then offers `:reset`. `rm -rf /` is
  refused with GNU's real message.
- **Progression:** XP (base + 50/25/10/0 bonus depending on hints used,
  × a difficulty multiplier) and nine ranks from *Newbie* to *sudo*. The top
  ranks also require specific challenges, so XP grinding alone never makes
  you root. Commands you learn show up as chips.
- **22 achievements, 9 of them hidden** (plus *First Blood* and *The Ascent* for the RPG) (for example *RTFM*, *Chaos Monkey*,
  *Loophole*, *Make Me a Sandwich*). They are data-driven.
- **Save/load:** one local JSON file in `user://`, written atomically. It
  stores the profile (XP, completions, hints, difficulty, stats,
  achievements, settings) and the machine state, so *Continue* resumes
  exactly where you left off, files included.

## Project structure

```text
road-to-sudo/
├── project.godot            autoloads: EventBus, SaveManager, Game
├── scenes/
│   ├── main/                main.tscn (root), game_screen.tscn
│   ├── world2d/             world2d.tscn (the 2D adventure)
│   ├── terminal/            terminal.tscn (the terminal widget)
│   └── ui/                  main_menu, objective_panel, progress_card,
│                            status_bar, toast, background.gdshader
├── scripts/
│   ├── core/                game.gd (composition root), event_bus.gd,
│   │                        save_manager.gd, meta_commands.gd, json_loader.gd
│   ├── filesystem/          VirtualFileSystem, VFSNode, Permissions,
│   │                        PathUtils, AccessContext, VfsResult
│   ├── machine/             Machine, MachineBuilder, ContentGenerators
│   ├── terminal/            ShellLexer, CommandParser, Expander, Shell,
│   │                        ShellSession, CommandContext, CommandRegistry,
│   │                        Completer, ExecutionOutcome, StringTools
│   ├── commands/            BaseCommand + one file per command (auto-discovered)
│   ├── challenges/          Challenge, ChallengeLibrary, ChallengeManager,
│   │                        ConditionEvaluator
│   ├── adventure/           AdventureWorld, AdventureState, AdventureManager
│   ├── world2d/             SpriteFactory, Player2D, Interactable, Blocker,
│   │                        World2D (the 2D overworld)
│   ├── progression/         PlayerProfile, Progression, DifficultySettings,
│   │                        AchievementSystem
│   └── ui/                  UiTheme + one script per scene
├── data/
│   ├── machines/            workstation.json, sandbox.json, mainframe.json
│   ├── adventure/           world.json (RPG region) + map.json (2D room layout)
│   ├── levels/              ordered chapters listing challenge ids
│   ├── challenges/          one JSON file per challenge
│   ├── achievements.json, difficulty.json, progression.json
│   ├── commands/            (reserved: per-command metadata, see roadmap)
│   └── tutorials/           (reserved: codex/lesson pages)
├── tests/                   run_tests.gd + suites, ui_smoke.tscn, dev helpers
├── tools/run_tests.sh
└── docs/                    ARCHITECTURE.md, ADDING_COMMANDS.md, ADDING_CHALLENGES.md
```

## Architecture in one screen

```text
 keyboard ─▶ TerminalView ──submitted──▶ Game.submit(line)
                  ▲                          │
                  │                  ":hint" │ everything else
                  │                          ▼
                  │                  MetaCommands     Shell.run_line()
                  │                                     │ CommandParser → Expander
                  │                                     │ → CommandRegistry → BaseCommand.execute(ctx)
                  │                                     ▼
                  │                              ExecutionOutcome
                  │                              (chunks + events + records)
                  │                                     │
   EventBus.command_output ◀────────────────────────────┤
   EventBus.narrate / challenge_* / xp / rank ◀─ ChallengeManager.observe()
                                                  Progression.record_outcome()
                                                  AchievementSystem.check_outcome()
```

- **Pure logic, no UI dependencies.** The VFS, shell, commands, challenges
  and progression are plain `RefCounted` classes. That is why the whole
  campaign can be tested headlessly.
- **Commands never touch the UI.** They write to `ctx.out()` / `ctx.err()`
  and report gameplay facts with `ctx.emit("permission_denied", …)`.
  Achievements and challenge reactions consume those events.
- **State-based validation.** Challenge success conditions look at the
  machine (files, modes, cwd, outputs seen, events), not at the command
  string.
- **`Game` is only a composition root.** It builds the systems, owns the
  active session and relays signals to the `EventBus`. The rules live in
  the subsystems.

Full details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Extending

- **New command:** add `scripts/commands/<name>_command.gd` extending
  `BaseCommand`. It is discovered automatically; no registration is needed.
  See [docs/ADDING_COMMANDS.md](docs/ADDING_COMMANDS.md).
- **New challenge:** add a JSON file to `data/challenges/` and list its id
  in a level file. No code is needed.
  See [docs/ADDING_CHALLENGES.md](docs/ADDING_CHALLENGES.md).

## Credits

Pixel art: **Kenney** (https://kenney.nl) — *Tiny Dungeon* and *Tiny Town*,
both **CC0 1.0** (public domain). Only the tiles used are bundled, under
`assets/tiles/` with their licenses and a `CREDITS.md`. Everything else
(engine, game, terminal font fallback) is original.

## Known limitations of this slice

These are honest gaps, not bugs:

- Scripts run line by line. There is no `if` / `for` / `while` or functions
  yet (planned for Level 11), and no `$(…)` command substitution.
- There are no interactive programs: `less` prints the whole file,
  `tail -f` doesn't follow, `su` can't prompt for a password, and there is
  no text editor.
- Globs support `*` and `?` but not `[abc]` classes. `find` has no `-o`
  (OR).
- There is one machine per session. The `Machine` model is ready for
  several (SSH, Level 10) but networking isn't simulated yet.
- The font is the system monospace font (JetBrains Mono, Fira Code, … and
  falling back to DejaVu Sans Mono). To bundle one, drop
  `assets/fonts/mono-regular.ttf` and `mono-bold.ttf` in place; `UiTheme`
  picks them up. There is no audio yet.
- "Unlocked commands" mark progress in the UI. Every simulated command can
  be run from the start, because blocking real commands would teach the
  wrong lesson. `sudo` is gated the Linux way, by `/etc/sudoers`.

## Roadmap (next steps)

Levels 0–6 and the Final (Road to sudo) are **built** — 40 challenges. Still
to come, each needing a new simulated subsystem:
1. **Networking** (a `Network` of hosts): `ss`, `ip`, `ping`, `curl`, `dig`.
2. **Packages** (a package DB): `apt`, `dpkg`.
3. **Services** (a `ServiceManager`): `systemctl`, `journalctl`.
4. **Level 6 & 10 · Networking and SSH:** a `Network` of `Machine`s,
   `ip` / `ss` / `curl` / `ssh` / `scp`, and keys in `~/.ssh`.
5. **Level 8 · Services:** a `ServiceManager` for `systemctl` / `journalctl`,
   with logs generated into `/var/log`.
6. **Level 11 · Bash:** control flow in the script interpreter (the parser
   already produces a list/pipeline AST to build on).
7. **More Adventure regions:** the RPG engine is data-driven — new regions,
   NPCs, enemies and bosses are JSON in `data/adventure/`. Networking/SSH and
   services will become new zones.
8. **Final level:** a broken production server that uses everything, ending
   with `sudo -i` → *"YOU MADE IT. Welcome to the other side of the
   prompt."* The `sudo` rank and the *Root Access* achievement already
   point at `final_road_to_sudo`.
