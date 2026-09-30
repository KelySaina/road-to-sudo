# Adding a challenge

Challenges are **data**. You need one JSON file in `data/challenges/` and its
id in a level file under `data/levels/`. No code.

## 1. Write the challenge

`data/challenges/l1_misplaced.json`:

```json
{
  "id": "l1_misplaced",
  "title": "Lost and found",
  "machine": "workstation",
  "xp": 120,
  "time_limit": 180,

  "briefing": ["Somebody saved the quarterly report... somewhere."],
  "expert_briefing": ["Ticket #88: quarterly report misplaced."],
  "tips": ["`find` walks directories for you. Quote your patterns: -name '*.pdf'"],

  "objective": "Find report-q2.txt anywhere under /home and copy it into ~/inbox/.",
  "expert_objective": "Recover report-q2.txt into ~/inbox.",

  "hints": [
    "Searching by hand would take forever. Is there a command that walks directories?",
    "`find /home -name 'report-q2.txt'` prints its path.",
    "`cp <that path> ~/inbox/`"
  ],
  "solution": "find /home -name report-q2.txt\ncp /home/player/old/stuff/report-q2.txt ~/inbox/",

  "setup": {
    "files": {
      "~/inbox": {"dir": true, "owner": "player", "group": "player"},
      "~/old/stuff/report-q2.txt": {"owner": "player", "group": "player", "content": "Q2: revenue up 12%\n"}
    },
    "remove": ["~/inbox/report-q2.txt"],
    "cwd": "~"
  },
  "protected": ["~/old/stuff/report-q2.txt"],

  "success": {"all": [
    {"type": "file_contains", "path": "~/inbox/report-q2.txt", "text": "revenue up"},
    {"type": "file_exists", "path": "~/old/stuff/report-q2.txt"}
  ]},

  "reactions": [
    {"when": {"type": "command_ran", "name": "mv", "args_contain": "report-q2"},
     "say": "You MOVED it. The objective said copy: the original is gone from its old place."}
  ],

  "explanation": "`find PATH -name PATTERN` searches a whole tree. Combine it with -exec to act on every match.",
  "unlocks": ["find", "cp"],
  "teaches": ["find", "copying"]
}
```

## 2. Put it in a level

`data/levels/level_01_filesystem.json` lists challenge ids in play order:

```json
{ "id": "filesystem", "order": 1, "title": "Level 1 — The Filesystem",
  "machine": "workstation", "challenges": ["l1_misplaced"] }
```

The campaign order is the levels sorted by `order`, then each level's list.

## 3. Test it

`tests/test_challenges.gd` → `test_every_solution_completes` automatically
checks two things for every challenge in the campaign: that it is **not**
complete before the player acts, and that its `solution` (one command per
line) **does** complete it. Also add:

- an alternative solution to `test_alternative_solutions`, because players
  won't type your solution; and
- a wrong answer to `test_wrong_answers_do_not_pass`.

Then run `tools/run_tests.sh`.

---

## Field reference

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique id; also the save key. |
| `title` | yes | Shown in the panel and the terminal rule. |
| `objective` | yes | Describe the **symptom or goal**, never the command. |
| `hints` | yes | Three hints, from vague to explicit (see Design rules). |
| `success` | yes | Condition tree (below). |
| `solution` | recommended | One possible answer, one command per line. It is shown after all hints (never in Expert). |
| `machine` | no | Machine to boot (`data/machines/<id>.json`). Leave it out to keep the current machine. |
| `fresh_machine` | no | `true` reboots a pristine machine even if it is the same one. |
| `briefing` / `expert_briefing` | no | Story lines typed out when the challenge starts. |
| `tips` | no | Beginner-only nudges shown with the briefing. |
| `expert_objective` | no | A vaguer, ticket-style objective for Expert mode. |
| `explanation` | no | "What just happened", shown after success (Beginner and Normal). |
| `xp` | no | Base XP (default 100). A bonus of 50/25/10/0 is added depending on hints used. |
| `time_limit` | no | Seconds. Expert gets +25 XP when solving within it. |
| `setup` | no | World changes applied when the challenge starts (below). |
| `protected` | no | Paths whose deletion triggers "Wait. Was that intentional?" and suggests `:reset`. |
| `reactions` | no | Contextual narration when a condition first becomes true. |
| `unlocks` | no | Commands added to the player's toolbox on completion. |
| `teaches` | no | Concept tags, used for stats now and for a codex later. |

Paths in `setup`, `success`, `reactions` and `protected` may start with `~`,
which means the player's home.

### `setup`

```json
"setup": {
  "restore": ["~/welcome.txt"],
  "files":   {"<path>": <file spec>},
  "remove":  ["~/projects"],
  "processes": [{"pid": 4444, "user": "player", "cpu": 97.0, "mem": 2.1, "cmd": "./miner"}],
  "services": {"nginx": {"active": false, "enabled": true, "sub": "dead"}},
  "cwd": "~"
}
```

They run in this order: `restore`, `files`, `remove`, `processes`, `services`, `cwd`.

`services` declares or overrides systemd units on the machine (see *Adding a
machine* for the full unit spec). A unit that fails to start until something is
fixed can carry a `needs` condition tree (same grammar as `success`): `systemctl
start` only brings it up when `needs` evaluates true — e.g.
`"needs": {"not": {"type": "file_contains", "path": "/etc/webapp/webapp.conf", "text": "port = 0"}}`.

- `restore` copies paths from the machine's **original definition**. Use it
  for files an earlier challenge might have let the player delete, so the
  challenge can never soft-lock.
- A **file spec** is the same format as the machine files:
  - `{"dir": true, "owner": "player", "group": "player", "mode": "750"}`
  - `{"content": "text\n"}`, or `{"lines": ["a", "b"]}`, which joins them
    with a newline
  - `{"generator": "auth_log" | "app_log" | "repeat", "params": {...}}` for
    large, seeded, deterministic content (see `ContentGenerators`)
  - plus optional `"owner"`, `"group"`, `"mode"` (octal string) and
    `"mtime"`

**Make every challenge self-sufficient.** Its setup must create everything
it relies on. Then *skip the basics*, `:skip` and `:reset` all keep working.

`:reset` restores a snapshot taken right after setup. After a
save/continue, when no snapshot exists, it rebuilds the pristine machine and
re-applies `setup`.

### Success conditions

Composites: `{"all": [...]}`, `{"any": [...]}`, `{"not": {...}}`.

| Leaf `type` | Parameters | True when |
|---|---|---|
| `file_exists` / `dir_exists` / `path_missing` | `path` | the path is (or isn't) there |
| `file_contains` | `path`, `text`, `ignore_case?` | the file content contains the text |
| `file_matches` | `path`, `regex` | the content matches a PCRE regex |
| `mode_is` | `path`, `mode: "755"` | the permission bits equal the mode exactly |
| `mode_has` / `mode_lacks` | `path`, `bits: "u+x"` | those bits are all set / all clear |
| `owner_is` | `path`, `owner?`, `group?` | owner and/or group match |
| `cwd_is` | `path` | the shell is in that directory |
| `user_is` | `user` | the shell runs as that user (for example `root` after `sudo -i`) |
| `env_is` | `name`, `value` | a variable has that value |
| `command_ran` | `name` (string or list), `args_contain?`, `exit_code?`, `cwd?`, `user?`, `scope?` | a matching command ran during this challenge (scripts and pipeline stages included) |
| `output_contains` / `output_matches` | `text` or `regex`, `scope?` | some command's stdout showed it |
| `event` | `name`, `data?` (equality), `data_contains?` | a command emitted that event |
| `process_running` / `process_absent` | `pid` or `cmd_contains` | process table state |
| `service_active` / `service_enabled` | `service`, `expect?` (default `true`) | a systemd unit is running / set to start at boot |

`scope` is `"any"` (the default: anything since the challenge started) or
`"last"` (only the line just entered).

**Prefer state over commands.** For example:

- "the file is executable and the backup ran" →
  `mode_has` + `file_contains`
- "they saw the codeword" → `output_contains`, whether they used `cat`,
  `less`, `head` or `grep`

Use `command_ran` only when running the command *is* the lesson (`whoami`,
`pwd`), and even then accept the alternatives (`id`, `echo $PWD`).

### Reactions

```json
{"when": <condition>, "say": "text", "kind": "reaction|tip|warning", "difficulty": ["beginner"]}
```

Each reaction fires at most once per attempt, the first time its condition
is true after a command. Use reactions to:

- **acknowledge investigation**: "Reading a script before running it:
  exactly what careful admins do."
- **catch a near miss**: "todo.txt landed in your home directory, not inside
  projects."
- **flag a loophole without accepting it**: "`bash backup.sh` worked, but
  the cron job calls ./backup.sh."
- **warn about bad practice**: `mode_has o+w` on a script →
  least-privilege warning.

Leave `difficulty` out to show a reaction in every mode. Beginner-only
reactions are the training wheels.

## Design rules (the "don't tell them the command" contract)

1. **Objectives describe the problem.** Write "The script exists. You can
   read it. Something prevents it from running.", not "Use chmod".
2. **Hints walk the mental model**, from observation to concept to
   command:
   - hint 1 says where to look,
   - hint 2 says what the concept is,
   - hint 3 is nearly the command.
   Never reveal a secret answer (a codeword, the intruder's name) in a hint.
3. **Reward investigation.** Put clues in the world: log lines, READMEs,
   error messages, file ownership.
4. **Accept every valid solution**, and test at least one alternative.
5. **Mistakes should be memorable, not fatal.** Protect key files, react to
   near misses, and make sure `:reset` can always recover.
6. **Realism first.** Real paths, real error messages, real permission
   semantics. If the game has to simplify, say so in the `man` page or the
   explanation.

## Adding a machine

`data/machines/<id>.json` defines `hostname`, `users` (uid, gid, groups
with the primary group first, home, shell), `sudoers`, `processes`,
`services` and `files`, using the same file specs as `setup`.

A `services` entry is a name → unit spec map, read by `systemctl` /
`journalctl`:

```json
"services": {
  "nginx": {
    "description": "A high performance web server",
    "active": true, "enabled": true, "sub": "running",
    "main_pid": 812, "exec": "/usr/sbin/nginx -g 'daemon off;'",
    "since": "Mon 2026-09-30 08:59:43 UTC",
    "journal": ["Sep 30 08:59:43 app-01 systemd[1]: Started nginx."],
    "needs": {}
  }
}
```

Only `active`/`enabled` are really needed; the rest have sane defaults.
`active` = running now, `enabled` = starts at boot. Changing a unit requires
root, so challenges expect the player to use `sudo`.

`MachineBuilder` adds the standard layout for you:

- `/bin /etc /home /tmp /usr /var/log /opt /dev`, with `/root` 700 and
  `/tmp` 777
- `/dev/null`
- `/etc/passwd`, `/etc/group`, `/etc/shadow` (640) and `/etc/sudoers`
  (440), generated from `users`
- a binary in `/usr/bin` for every registered command

A user is a sudoer when they are in the `sudo` or `wheel` group, or listed
in `sudoers`.
