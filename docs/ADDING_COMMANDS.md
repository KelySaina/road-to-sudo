# Adding a command

A command is one GDScript file in `scripts/commands/` that extends
`BaseCommand`. `CommandRegistry` scans that folder at startup, so there is
nothing to register. The command also shows up automatically in `help`,
`man`, Tab completion and "Did you mean", and as a binary under `/usr/bin`
(so `which` and `ls /usr/bin` find it).

## The whole recipe

`scripts/commands/rev_command.gd`:

```gdscript
class_name RevCommand
extends BaseCommand


func get_command_name() -> String: return "rev"
func get_category() -> String: return "text"
func get_summary() -> String: return "reverse each line of text"
func get_usage() -> String: return "rev [FILE...]"
func get_manual() -> String:
	return "Prints every line backwards. Reads stdin when no FILE is given:\n  echo stressed | rev"


func execute(ctx: CommandContext) -> int:
	var read := ctx.read_sources(ctx.args())
	for src in read.sources:
		for line in StringTools.lines(src.content):
			ctx.out(str(line).reverse() + "\n")
	return 1 if read.failed else 0
```

That's all. `echo stressed | rev` prints `desserts`, `rev /nope` prints
`rev: /nope: No such file or directory`, and `man rev` works. This exact
file was verified against the engine.

Then add a test to `tests/test_shell.gd` (see "Testing" below).

## The BaseCommand contract

| Method | Purpose |
|---|---|
| `get_command_name()` | The name typed at the prompt. **Required.** |
| `get_aliases()` | Other names, e.g. `["more"]` for `less`. |
| `get_summary()` | One line for `help` and inline suggestions. |
| `get_usage()` | Synopsis for `man` and usage errors. |
| `get_manual()` | Body of the `man` page. Keep it short and practical, with an example. |
| `get_category()` | Groups `help` output: `basics files text permissions users processes system shell`. |
| `execute(ctx) -> int` | Does the work. Returns the exit status. |

Helpers:

- `parse_options(args, value_short, value_long)` is getopt-style parsing.
  It handles `-la`, `-n 5`, `-n5`, `--lines=5`, `--lines 5` and `--`.
- `usage_error(ctx, message)` prints the message plus usage and returns 2.

## CommandContext: the only world a command sees

| Call | Meaning |
|---|---|
| `ctx.args()` | Arguments after expansion: quotes removed, `$VAR`, `~` and globs already resolved. |
| `ctx.out(text, style)` | Writes to stdout. It goes into pipes and redirects; `style` only colors screen output (see below). |
| `ctx.err(text)` | Writes to stderr. |
| `ctx.fail(subject, reason, code=1)` | Prints `cmd: subject: reason` and returns `code`. Emits `permission_denied` automatically when the reason is `Permission denied` or `Operation not permitted`. |
| `ctx.read_sources(operands)` | cat-style input: reads each file (or stdin when there are none, or for `-`), reports errors itself, and returns `{sources: [{name, content}], failed}`. |
| `ctx.resolve(path)` | Absolute path from the current directory. |
| `ctx.vfs()` / `ctx.machine()` / `ctx.session` | The simulated world. |
| `ctx.access()` | Who is asking. Pass it to every VFS call so permissions are enforced. |
| `ctx.to_screen` | `false` when stdout is a pipe or a file (the "isatty" of this world). `ls` uses it to print one name per line. |
| `ctx.stdin` / `ctx.has_stdin` | Piped or redirected input. |
| `ctx.emit(name, data)` | Reports a gameplay fact (see Events). |
| `ctx.spawn(argv)` + `ctx.shell.invoke(child)` + `ctx.absorb(child)` | Runs another command inside this one, the way `sudo` and `find -exec` do. |

### Conventions that keep the simulation honest

1. **Always go through the VFS with `ctx.access()`.** Never read
   `node.content` directly for user-facing reads. `read_file`,
   `write_file`, `list_dir`, `lookup`, `make_dir`, `remove`, `copy` and
   `move` already check `r/w/x` on the file and search (`x`) permission on
   every directory along the path. Pass `null` only for "kernel" work such as
   world building.
2. **Use real error wording**: `No such file or directory`,
   `Permission denied`, `Is a directory`, `Operation not permitted`. Players
   will meet these messages on real machines, and `VirtualFileSystem` has
   them as constants.
3. **Use real exit codes**: `0` for success, `1` for failure, `2` for a
   usage error. The shell itself returns `126` (not executable) and `127`
   (not found).
4. **Don't talk to the UI.** Commands never touch nodes or the EventBus.
   That is what keeps them testable headlessly.
5. **Emit events for anything a challenge or achievement might care
   about.**

### Output styles

`ctx.out(text, style)` takes a style name that `UiTheme.STYLE_COLORS` maps
to a color. The styles are: `dir`, `exec`, `hidden`, `meta`, `dim`,
`header`, `match`, `path` and `warn`. The style never reaches pipes or
files, which only ever get plain text.

### Events

Existing events that challenges and achievements already listen for:

`permission_denied`, `file_deleted`, `file_created`, `file_moved`,
`file_read`, `cwd_changed`, `listed`, `mode_changed`, `owner_changed`,
`identity_checked`, `grep_used`, `find_used`, `manual_read`, `sudo_attempt`,
`sudo_denied`, `sudo_ran`, `root_shell`, `su_failed`, `process_killed`,
`variable_set`, `script_succeeded`, `rm_root_attempt`, `command_not_found`.

The shell itself adds `pipe_used {length}`, `chain_used {op}` and
`redirect_used {append, path}`.

Any new event name works immediately in challenge JSON
(`{"type": "event", "name": ...}`) and in achievements (`{"event": ...}`).

## Commands that change the session

Some commands change the shell rather than files:

- `cd` calls `ctx.session.set_cwd()`.
- `export` writes `ctx.session.env`.
- `sudo` and `su` call `ctx.session.switch_user()`, and `exit` calls
  `pop_user()`.
- `clear` sets `ctx.outcome.clear_screen`.

`Game` refreshes the prompt when it sees `cwd_changed`, `root_shell` or a
user change.

## Testing

Add a case to `tests/test_shell.gd`:

```gdscript
func test_rev() -> void:
	var sh := new_shell()
	check_eq(out(sh, "echo stressed | rev"), "desserts\n", "rev via pipe")
	check(text(sh, "rev /nope").contains("No such file"), "rev error")
```

Run `tools/run_tests.sh`. The suite also checks that at least 40 commands
are registered, which catches a broken auto-discovery.

If you add a new `class_name`, the editor refreshes its class cache
automatically. From the CLI, run `godot --headless --path . --import` once.
