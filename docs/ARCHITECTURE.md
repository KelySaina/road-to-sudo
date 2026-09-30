# Architecture

Road to sudo is a **Linux simulator with a game on top**. The simulator
knows nothing about the game, and the game knows nothing about how commands
work. Everything below the UI is plain `RefCounted` GDScript: the whole
campaign runs headlessly in tests.

```text
┌──────────────────────────── UI (scenes/, scripts/ui/) ─────────────────────────────┐
│ Main ─ MainMenu │ GameScreen ─ TerminalView · StatusBar · ProgressCard · ObjectivePanel │
│ ToastStack · UiTheme (palette, fonts, styleboxes, type variations)                  │
└───────────────▲──────────────────────────────────┬─────────────────────────────────┘
                │ EventBus signals                  │ Game.submit(line)
┌───────────────┴──────────── core/ (autoloads) ────▼────────────────────────────────┐
│ Game: composition root · MetaCommands (:hint…) · SaveManager · EventBus             │
└──────┬───────────────────────┬──────────────────────────┬─────────────────────────┘
       │                       │                          │
┌──────▼──────────┐   ┌────────▼─────────┐   ┌────────────▼────────────┐
│ challenges/     │   │ progression/     │   │ terminal/ + commands/   │
│ ChallengeLibrary│   │ PlayerProfile    │   │ Shell ← CommandParser   │
│ ChallengeManager│   │ Progression      │   │   ← ShellLexer, Expander│
│ Condition-      │   │ Difficulty-      │   │ CommandRegistry         │
│   Evaluator     │   │   Settings       │   │ BaseCommand × 48        │
│                 │   │ AchievementSystem│   │ ShellSession, Completer │
└──────┬──────────┘   └──────────────────┘   └────────────┬────────────┘
       │ reads state                                       │ operates on
┌──────▼───────────────────────────────────────────────────▼──────────────┐
│ machine/: Machine (host, users, processes, sudoers) · MachineBuilder     │
│ filesystem/: VirtualFileSystem · VFSNode · Permissions · PathUtils       │
└──────────────────────────────────────────────────────────────────────────┘
                 data/*.json: machines, challenges, levels, rules
```

## One line of input, end to end

1. **`TerminalView`** echoes the prompt and the line, then emits
   `submitted(line)`.
2. **`Game.submit(line)`** routes the line:
   - `:…` → `MetaCommands` (game actions).
   - An empty line after a completed objective → `advance()`.
   - Anything else → `Shell.run_line()`.
3. **`Shell`** runs the line:
   - `CommandParser.parse()` builds a list of pipelines joined by
     `;` / `&&` / `||`. Each command has its own redirects.
   - For each command, `Expander` resolves `~`, then `$VAR`, then globs. It
     respects quoting segment by segment: single quotes are literal, double
     quotes expand variables but not globs.
   - Redirects are opened *before* the command runs, as in bash (so
     `> file` truncates first).
   - `invoke()` dispatches, in this order:
     1. a `NAME=value` assignment;
     2. a path (`./x.sh`), which goes through a real exec-permission check
        and is then interpreted line by line;
     3. a registered command;
     4. otherwise "Command 'x' not found. Did you mean:".
   - Every simple command is logged in `ShellSession.command_log` as
     `{name, args, exit_code, stdout, stderr, depth, user, cwd}`.
4. The result is an **`ExecutionOutcome`** with three parts:
   - `chunks`: styled text for the screen;
   - `events`: gameplay facts such as `permission_denied`,
     `file_deleted` or `pipe_used`;
   - `records`: the command-log entries this line produced.
5. `Game` passes the outcome on, in this order:
   1. `EventBus.command_output`, so the terminal prints it;
   2. `Progression.record_outcome`, for stats;
   3. `AchievementSystem.check_outcome`;
   4. `ChallengeManager.observe`, which handles protected files, runs
      reactions and evaluates success.
6. When the objective is met:
   - `ChallengeManager` emits `challenge_completed` with a score.
   - `Game` records XP and unlocks. It then emits the events so the player
     reads *complete → new commands → rank up → press Enter*, in that order.
   - The game autosaves.

## Key decisions and why

**The simulated OS is real enough to be wrong in the right ways.**
Permissions follow Unix semantics:

- owner, then group, then others, taking the first class that applies;
- search (`x`) permission is checked on every directory along a path;
- root bypasses everything except that executing needs at least one `x`
  bit;
- `chmod` is owner-only and `chown` is root-only.

Error text matches coreutils and bash. Players meet the same messages on a
real server.

**State-based validation.** `ConditionEvaluator` checks the machine
(files, modes, cwd, users, processes, outputs the player has *seen*,
events). It does not match the command string. That is what makes multiple
solutions work: `chmod u+x`, `chmod 755` and `chmod +x` all pass. It also
lets the game refuse "clever" non-fixes: `bash backup.sh` runs the script
but leaves it non-executable, and the challenge knows.

**Events instead of coupling.** Commands `emit()` facts. They don't know
that achievements, challenge reactions or stats exist. Adding a new
achievement, or a reaction to a new situation, is a JSON edit.

**`isatty` exists.** `CommandContext.to_screen` is false when stdout is
piped or redirected. That is why `ls` prints one name per line into a pipe
(`ls | wc -l` is correct), and why colors never leak into files.

**Game commands are prefixed with `:`.** `:hint` and `:reset` are clearly
not Linux. The Linux layer never has to pretend a fake command exists.

**Composition root, not a god object.** `Game` builds the systems, owns the
active `ShellSession` and relays signals. Rules live in `Shell`,
`ChallengeManager`, `Progression` and `AchievementSystem`, each testable
alone. UI scripts read state from `Game` and react to `EventBus`. They
never mutate game state except through `Game.submit()`, so mouse and
keyboard share one code path (the Hint button literally submits `:hint`).

**Nodes don't know their parent.** `VFSNode` has no parent pointer, which
avoids `RefCounted` reference cycles and leaks. Paths are always resolved
from the root.

**Deterministic content.** Big files (3,000-line logs) are generated from a
seed at build time (`ContentGenerators`). Challenge JSON stays small and
every player gets the same haystack.

## Persistence

`SaveManager` writes a single JSON file, `user://road_to_sudo_save.json`.
It writes to a `.tmp` file first and then renames it, so a crash can't
corrupt the save. The file contains:

```text
{
  "profile": PlayerProfile.to_dict(),   xp, difficulty, completed{id: {xp, hints, solution, at, seconds}},
                                        skipped, hints_used, solutions_seen, unlocked_commands,
                                        achievements{id: time}, stats{...}, settings{...}
  "worlds": {
    "campaign": {machine_id, machine: Machine.to_dict(), cwd, history, challenge},
    "practice": {...}
  }
}
```

*Continue* restores the campaign world and resumes the current challenge
**without** re-running its setup, so half-finished work survives. The game
autosaves every 8 lines, on every completion, on `:menu`, and when the
window closes.

## Difficulty

`data/difficulty.json` controls each mode:

- tips shown or not;
- explanations shown or not;
- maximum hints;
- whether the solution is available;
- whether `:skip` is allowed;
- inline command help under the prompt;
- the XP multiplier;
- the Expert time bonus.

Challenges can add `expert_objective` and `expert_briefing`, and reactions
can be limited to certain modes. "Skip the basics" is also data-driven: it
marks challenges as skipped up to `skip_basics_to` and still unlocks their
commands.

## Extension points for upcoming levels

| Need | Where it goes |
|---|---|
| New commands | `scripts/commands/*_command.gd` (auto-discovered) |
| Networking / SSH | a `Network` holding several `Machine`s. `ssh` pushes a session for another machine, the same way `sudo -i` pushes a user (`ShellSession.switch_user` / `pop_user` show the pattern). |
| Services | a `ServiceManager` on `Machine` (`systemctl` starts and stops entries; `journalctl` reads generated logs) |
| Password prompts / interactive tools | an `ExecutionOutcome.prompt_request` that `TerminalView` fulfils, with the answer fed back to the command |
| Bash control flow | extend `Shell.run_script` to parse `if` / `for` / `while` blocks on top of `CommandParser` |
| Live processes | tick `Machine.processes` from `StatusBar`'s one-second timer (respawning hogs, jobs) |
| Codex / lessons | `data/tutorials/`, keyed by the challenges' `teaches` tags |

## Testing

- `tests/run_tests.gd` (SceneTree script) runs `test_core.gd`,
  `test_shell.gd` and `test_challenges.gd`. They are pure logic with no
  autoloads.
- `tests/ui_smoke.tscn` runs with autoloads and real scenes and plays the
  full campaign through the widget. It has a watchdog, so an aborted
  coroutine fails the run instead of hanging.
- `tools/run_tests.sh` runs both and fails on any `SCRIPT ERROR`.
