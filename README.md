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

This is an early build with a lot in it: a full **14-level campaign (64
challenges)** that takes you from `whoami` to taking **root on a burning
production server**, plus a **2D platformer adventure mode**. It teaches the
real toolkit — files and permissions, text and pipes, processes and logs,
services, networking, packages, git, SSH and Bash scripting — in two languages,
with music and sound.

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

- `tests/run_tests.gd`: 1898 assertions over the VFS, permissions, parser,
  every command, progression and achievements, plus the localisation layer
  (French placeholder-parity, English fallback) and the audio layer (every
  music track and sound effect exists). It plays **every challenge's solution
  plus alternative solutions**, and checks that wrong answers and half-fixes do
  not pass.
- `tests/adventure_smoke.gd`: plays the whole RPG region end to end — every
  fight, the damage traps, the respawning boss and the death/reboot — 62
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
| `A` `D` / `←` `→` | run (Adventure mode) |
| `Space` / `W` | jump (Adventure mode) |
| `E` | act on a console or portal (Adventure mode) |
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
- **Campaign — 14 levels, 64 challenges** (state-checked, so any valid solution
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
- **Level 7 · Services & the Journal**, 4: on the app server `app-01`, drive
  `systemctl` (`status`/`start`/`enable`/`stop`/`disable`) to bring a downed web
  service up and set it to boot, shut down an insecure `telnet` daemon, then
  diagnose a *failed* service with `journalctl -u`, fix its config, and restore
  it. Changing a service needs `sudo`.
- **Level 8 · Networking**, 4: on `net-01`, read your own address with `ip`,
  hunt a backdoor listener with `ss -tlnp`, pull a health endpoint with `curl`,
  and fix a name that won't resolve by mapping it in `/etc/hosts` (`dig`,
  `ping`).
- **Level 9 · Package Management**, 4: install a missing tool with `apt`
  (dependencies pulled in for you), audit an installed version with `dpkg`,
  spot a risky package that shouldn't be on a server, and `apt remove` it.
- **Level 10 · Version Control with Git**, 4: `git init` / `add` / `commit` /
  `status` / `log` on a real index-and-commits model that diffs the working
  tree live — put a project under version control, keep a `.env` secret out
  with `.gitignore`, stage only what's ready, and build a two-commit history.
- **Level 11 · SSH & Remote Servers**, 4: from a jump host, `ssh-keygen` a key,
  `ssh` into a broken web server (your prompt and the whole session move to the
  remote box), `scp` a log back, and end an incident on a machine you never
  touch — `exit` brings you home.
- **Level 12 · Bash: Loops & Logic**, 4: batch-rename files with a `for` loop,
  filter with `if` + `test` (`[ ... ]`), drain a queue with `while`, and glue
  commands together with command substitution `$( )`.
- **Final · Road to sudo**: a broken production server, no hand-holding —
  investigate, `sudo -i`, stop the rogue root process, and hold the throne.
- **Adventure mode — "The Ascent to Root" (Skill Worlds):** a side-scrolling 2D
  **platformer** built on one loop — **learn a skill, then prove it.** You run
  (`A`/`D`) and jump (`Space`) an operator through **twelve worlds** that mirror
  the campaign — filesystem, logs, processes, find, cut, **services, networking,
  packages, git, ssh and bash** — each one a course built from pits, ledges,
  spike strips, patrolling rovers, pulsing emitters, two-step stairs, zig-zag
  towers and lifts over gaps you can't jump — every world picks its own obstacles
  and its own tile colour in `worlds.json`.
  Glowing **skill orbs** sit on the ledges, so every command costs you a jump. Reach one and you learn it — a card explains
  the command, and then it drops you onto a **real prompt to try it on**: the
  world's files, services, package database or network are laid out so the
  example actually runs, and nothing there is
  graded. Take every orb and the world's **trial console** unlocks: press **E**
  and solve a real problem with exactly those skills — make a script run
  (`chmod`), name a log intruder (`grep|sort|uniq`), stop a miner (`ps`,`kill`),
  name the service that crashed (`systemctl`/`journalctl`), trace a backdoor port
  (`ss`), audit an installed version (`dpkg`), make the first commit (`git`), pull
  a file off another box (`scp`), or flag every error log with a loop (`for`/`if`)…
  Any valid solution passes, you get a "what you learned", and the **portal** to
  the next world opens. No HP, no lives and nothing kills you — touch a hazard or
  fall in a pit and you're set back on the last ground you stood on, and told so.
  The camera leads where you run, the vector-drawn operator has a real run cycle
  with poses for rising and falling, and each course is backed by parallax layers
  of machine receding into the dark. It ends at the Throne of root: the
  **sudo orb** earns you the right, and you become root to end the impostor
  (*"YOU MADE IT."*). Trial XP feeds the same ranks; the run is saved.
  Full write-up: [docs/ADVENTURE.md](docs/ADVENTURE.md).
- **Practice Lab:** a separate sandbox machine with no objectives and no
  score.
- **74 simulated commands:**
  - basics: `pwd cd ls echo clear help man history learn`  (`learn` is a
    friendly cheat sheet of what every command does, with examples)
  - files: `cat less touch mkdir rmdir rm cp mv find tree stat file`
  - text: `grep head tail wc sort uniq cut tr`
  - permissions: `chmod chown/chgrp umask`
  - users: `whoami id groups who su sudo`
  - processes: `ps top kill pkill pgrep`
  - services: `systemctl journalctl`
  - network: `ip ss ping dig/host curl`
  - remote: `ssh scp ssh-keygen`
  - packages: `apt/apt-get dpkg`
  - version control: `git` (init/add/commit/status/log/diff)
  - system: `hostname uname date`
  - shell: `bash/sh env/printenv export unset which exit true false test/[`
- **Shell features:** pipes, `>`, `>>`, `<`, `2>`, `2>&1`, `>&2`, `&&`,
  `||`, `;`, quoting, `$VAR` / `${VAR}` / `$?`, `~` expansion, `*` / `?`
  globs, `NAME=value`, command substitution `$( )` / `` ` ` ``, and **control
  flow** — `for`, `while` / `until`, `if` / `elif` / `else`, with `test` / `[ ]`
  — both on one line (`for f in *; do …; done`) and as multi-line blocks in a
  script. Scripts take `$1..$9` and `exit N`, and running one checks real
  permissions: `./x.sh` needs `x`, `bash x.sh` only needs `r`.
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
- **Languages:** the interface switches between **English and Français** in
  Settings. The Linux the game teaches stays English on purpose — terminal
  output, prompts and the commands in every solution — while the teaching
  layer around it (UI, objectives, hints, narration, `man`/`learn`) is
  localised. Translation is keyed by the English source string, so a missing
  entry simply shows English. See **Translation** under *Extending*.
- **Sound:** background music that crossfades between the menu, the campaign,
  Adventure and the victory screen, plus sound effects wired to the events
  that matter — a command error, an objective cleared, a rank-up, an orb
  taken, a jump, a hazard setback. Music and SFX each have an on/off toggle in
  Settings. All audio is CC0 (Mirrorshade + Kenney; see
  `assets/sounds/CREDITS.md`).

## Project structure

```text
road-to-sudo/
├── project.godot            autoloads: EventBus, SaveManager, Game, Audio
├── scenes/
│   ├── main/                main.tscn (root), game_screen.tscn
│   ├── world2d/             world2d.tscn (the 2D adventure)
│   ├── terminal/            terminal.tscn (the terminal widget)
│   └── ui/                  main_menu, objective_panel, progress_card,
│                            status_bar, toast, background.gdshader
├── scripts/
│   ├── core/                game.gd (composition root), event_bus.gd,
│   │                        save_manager.gd, meta_commands.gd, json_loader.gd,
│   │                        i18n.gd (localisation), audio.gd (music + SFX)
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
│   ├── world2d/             SpriteFactory, Player2D (platformer controller),
│   │                        Hazard, MovingPlatform, Interactable, Blocker,
│   │                        World2D (builds the 2D courses)
│   ├── progression/         PlayerProfile, Progression, DifficultySettings,
│   │                        AchievementSystem
│   └── ui/                  UiTheme + one script per scene
├── data/
│   ├── machines/            workstation.json, sandbox.json, mainframe.json
│   ├── adventure/           worlds.json (the twelve skill worlds)
│   ├── levels/              ordered chapters listing challenge ids
│   ├── challenges/          one JSON file per challenge
│   ├── achievements.json, difficulty.json, progression.json
│   ├── commands/            (reserved: per-command metadata, see roadmap)
│   └── tutorials/           (reserved: codex/lesson pages)
├── tests/                   run_tests.gd + suites, ui_smoke.tscn, dev helpers
├── tools/run_tests.sh, extract_tiles.py
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
- **Translation:** the UI language is switchable in Settings (English /
  Français), and **French is complete** — the whole UI, all 64 campaign
  challenges, every Adventure world, and all command manuals. Translation is
  keyed by the English source string: the code and data keep their English, and
  `data/i18n/<locale>.json` maps it to the target language. A string with no
  entry falls back to English, so a partial translation still plays. **What is
  the Linux being taught stays English on purpose** — the terminal's own output
  (`ls` columns, `Permission denied`, prompts, file contents), every command in
  a solution or example, and each command's usage *synopsis* (`ls [-a] [-l]
  …`). Only the teaching layer around it is localised: UI, objectives, hints,
  narration, and the prose of `man`/`learn`/`help`. `python3
  tools/extract_strings.py` reports the full translatable surface;
  `--missing <locale>` lists what a locale still lacks. `tests/test_i18n.gd`
  guards the fallback, that content under `setup/` is never translated, and that
  every translated string keeps the `%`-placeholders of its English source.

## Credits

Adventure mode's terrain and hazards come from **"Sci-fi Platformer Tileset" by
Michele 'Buch' Bucelli** (https://opengameart.org/content/sci-fi-platformer-tileset),
**CC0 1.0** (public domain). The sheet is not bundled: `tools/extract_tiles.py`
fetches it and slices out only the tiles the game uses — five colour sets of
block/edge tiles, plus spikes, a rover and a pulse emitter.

The console and the portal are original, authored as 16x16 colour maps in
[scripts/world2d/sprite_factory.gd](scripts/world2d/sprite_factory.gd) so they
sit in the same palette as the rest of the UI and live in a text diff rather
than a binary. A PNG in `assets/tiles/<name>.png` overrides either of them. The
operator is not pixel art: it is vector-drawn in
[scripts/world2d/character_sprite.gd](scripts/world2d/character_sprite.gd) and
stays crisp at any zoom.

**Audio** is CC0 too: background music is *Mirrorshade* by James Gargette, and
the sound effects are from **Kenney — Interface Sounds** (kenney.nl). Only the
tracks used are kept, renamed to their role; see `assets/sounds/CREDITS.md`.

Everything else — engine, game, terminal font fallback — is original. See
`assets/tiles/CREDITS.md`.

## Known limitations of this slice

These are honest gaps, not bugs:

- Control flow covers `for` / `while` / `until` / `if`, `case`, shell
  **functions** (`name() { ... }`), `test` / `[ ]`, `$( )` / backticks and
  `$(( ))` arithmetic — single-line or multi-line in scripts. Functions don't
  have a `return` builtin yet (the exit code is the last command's).
- `nano` (edit), `less` (page/search), `tail -f` (follow a live log) and `su`
  (masked password prompt) are real interactive programs now. `su` checks the
  target's password (locked accounts fail → use sudo); `sudo` keeps its policy
  check, like real Linux.
- Globs support `*`, `?` and `[abc]` / `[a-z]` / `[!abc]` classes. `find`
  supports `-o` / `-a`, but not `\( \)` grouping.
- The font is the system monospace font (JetBrains Mono, Fira Code, … and
  falling back to DejaVu Sans Mono). To bundle one, drop
  `assets/fonts/mono-regular.ttf` and `mono-bold.ttf` in place; `UiTheme`
  picks them up.
- "Unlocked commands" mark progress in the UI. Every simulated command can
  be run from the start, because blocking real commands would teach the
  wrong lesson. `sudo` is gated the Linux way, by `/etc/sudoers`.

## Roadmap (next steps)

**Every spec topic is now built** — Levels 0–12 and the Final, 64 challenges.
Each recent level added a small subsystem to `Machine` and a command or two:
Level 7 (Services) `systemctl` / `journalctl`; Level 8 (Networking) `ip` / `ss`
/ `ping` / `dig` / `curl`; Level 9 (Packages) `apt` / `dpkg`; Level 10 (Git) the
`git` command; Level 11 (SSH) whole-session `ssh` into remote machines, `scp`
and `ssh-keygen`; Level 12 (Bash) `for` / `while` / `if` / `test` and `$( )` in
the shell interpreter.

**Adventure mode now mirrors the campaign too** — twelve worlds, from the
filesystem up to the Throne of root, covering services, networking, packages,
git, ssh and bash. A world is `orbs` + a `trial` in
`data/adventure/worlds.json`, plus the `course` of platforming segments and the
tile `palette` it is built from; a trial can lay down files, processes,
services, a package database or a network, so a new world is still (almost
always) pure JSON.

**Interactive programs landed** — the terminal gained a full-screen overlay
layer, and three real programs on it: `nano FILE` (edit — `^O` save, `^X` exit;
saving re-grades, so a challenge can be solved by *editing* a file), `less`
(page, `/`-search, `q` to quit) and `tail -f` (follow a log, new lines streaming
in live until `^C`/`q`). They share one overlay pattern a command opens by
emitting an event.

**The shell interpreter is close to complete** — `case`, shell functions,
`$(( ))` arithmetic, `[abc]` glob classes and `find -o` all landed, on top of the
existing `for`/`while`/`if`/`test`/`$( )`. What's left is small: a `return`
builtin for functions and `\( \)` grouping in `find`.

**Every interactive program is in** — the terminal now has `nano`, `less`,
`tail -f` and a masked `su` prompt, all on one full-screen overlay layer a
command opens by emitting an event.

What's left is polish and reach, not engine:
- **Adventure trial overlays** — wire the editor/pager into the 2D trial console
  (today they're campaign/practice only).
- **A progress / stats screen** — surface rank, skills, achievements and
  per-level/world completion in one place.

The Final is done: a broken production server that uses everything, ending with
`sudo -i` → *"YOU MADE IT. Welcome to the other side of the prompt."*
