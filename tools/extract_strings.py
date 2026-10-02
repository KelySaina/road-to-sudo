#!/usr/bin/env python3
"""Collect every English string the game can localise.

Mirrors the rules in scripts/core/i18n.gd: the same TRANSLATABLE keys and the
same NEVER subtrees, so what this prints is exactly what I18n.t() will look up
at runtime. Used to build and audit data/i18n/<locale>.json.

    python3 tools/extract_strings.py            # report counts
    python3 tools/extract_strings.py --missing fr   # keys with no French yet
    python3 tools/extract_strings.py --json      # all keys, as a JSON array
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Keep in step with scripts/core/i18n.gd.
TRANSLATABLE = {
    "title", "subtitle", "description", "objective", "expert_objective",
    "briefing", "expert_briefing", "tips", "hints", "explanation",
    "say", "intro", "outro", "learned", "name", "teaches", "label", "blurb", "desc",
}
NEVER = {"setup", "success", "when", "params", "respawn", "solution",
         "unlocks", "reactions_from", "files", "processes"}

# Content files that go through JsonLoader.load_content_*.
CONTENT = [
    "data/challenges/*.json", "data/levels/*.json", "data/adventure/worlds.json",
    "data/achievements.json", "data/cheatsheet.json", "data/progression.json",
    "data/difficulty.json",
]
# Scripts whose user-facing literals are wrapped in I18n.t().
UI_SCRIPTS = ["scripts/ui/*.gd", "scripts/world2d/*.gd", "scripts/core/*.gd",
              "scripts/challenges/*.gd", "scripts/adventure/*.gd"]


def walk(value, out, key=None):
    if isinstance(value, list):
        if key in TRANSLATABLE:
            for v in value:
                if isinstance(v, str):
                    out.add(v)
                else:
                    walk(v, out)
        else:
            for v in value:
                walk(v, out)
        return
    if not isinstance(value, dict):
        return
    for k, v in value.items():
        if k in NEVER:
            continue
        if k in TRANSLATABLE:
            if k == "teaches" and not isinstance(v, str):
                continue
            if isinstance(v, str):
                out.add(v)
            else:
                walk(v, out, k)
        else:
            walk(v, out)


def content_strings():
    out = set()
    for pattern in CONTENT:
        for path in sorted(ROOT.glob(pattern)):
            walk(json.loads(path.read_text()), out)
    return out


def help_strings():
    """The summary/usage/help text on every command."""
    out = set()
    for path in sorted((ROOT / "scripts" / "commands").glob("*.gd")):
        src = path.read_text()
        for m in re.finditer(r'func (get_summary|get_usage|get_help|get_manual)\(\)[^\n]*:\s*\n?\s*return\s+"""(.*?)"""', src, re.S):
            out.add(m.group(2))
        for m in re.finditer(r'func (get_summary|get_usage|get_help|get_manual)\(\)[^:]*:\s*return\s+"((?:[^"\\]|\\.)*)"', src):
            out.add(m.group(2).replace('\\n', '\n').replace('\\"', '"'))
    return out


def ui_strings():
    """Literals already wrapped in I18n.t("...")."""
    out = set()
    for pattern in UI_SCRIPTS:
        for path in sorted(ROOT.glob(pattern)):
            src = path.read_text()
            for m in re.finditer(r'I18n\.t\(\s*"((?:[^"\\]|\\.)*)"\s*\)', src):
                out.add(m.group(1).replace('\\n', '\n').replace('\\"', '"'))
            # Static .tscn labels localised at load: a `"%Node": "English"` map
            # and `_set_label("path", "English")` calls in main_menu.gd.
            for m in re.finditer(r'"%\w+":\s*"((?:[^"\\]|\\.)*)"', src):
                out.add(m.group(1).replace('\\n', '\n').replace('\\"', '"'))
            for m in re.finditer(r'_set_label\([^,]+,\s*"((?:[^"\\]|\\.)*)"\s*\)', src):
                out.add(m.group(1).replace('\\n', '\n').replace('\\"', '"'))
    return out


def main() -> int:
    groups = {"content": content_strings(), "help": help_strings(), "ui": ui_strings()}
    every = set().union(*groups.values())
    every.discard("")

    if "--json" in sys.argv:
        print(json.dumps(sorted(every), ensure_ascii=False, indent=2))
        return 0
    if "--missing" in sys.argv:
        locale = sys.argv[sys.argv.index("--missing") + 1]
        path = ROOT / "data" / "i18n" / ("%s.json" % locale)
        have = json.loads(path.read_text()) if path.exists() else {}
        missing = sorted(s for s in every if not have.get(s))
        print(json.dumps(missing, ensure_ascii=False, indent=2))
        print("# %d of %d still untranslated" % (len(missing), len(every)), file=sys.stderr)
        return 0

    for name, strings in groups.items():
        chars = sum(len(s) for s in strings)
        print("%-8s %4d strings  %7d chars" % (name, len(strings), chars))
    print("%-8s %4d strings  %7d chars" % ("TOTAL", len(every), sum(len(s) for s in every)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
