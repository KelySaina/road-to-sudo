#!/usr/bin/env bash
# Runs the engine test suite and the UI smoke test headlessly.
#   GODOT=/path/to/godot tools/run_tests.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

# First run on a fresh checkout: build the class cache / import resources.
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "== engine tests"
out=$("$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1)
echo "$out" | grep -E "assertions|FAIL|ERROR" || true
echo "$out" | grep -q " 0 failed" || { echo "engine tests failed"; exit 1; }

echo "== adventure playthrough"
out=$("$GODOT" --headless --path . --script res://tests/adventure_smoke.gd 2>&1)
echo "$out" | grep -E "adventure:|FAIL" || true
echo "$out" | grep -q " 0 failed" || { echo "adventure tests failed"; exit 1; }

echo "== UI smoke test"
out=$("$GODOT" --headless --path . res://tests/ui_smoke.tscn 2>&1)
echo "$out" | grep -E "UI smoke|FAIL|SCRIPT ERROR" || true
echo "$out" | grep -q "UI smoke: OK" || { echo "UI smoke test failed"; exit 1; }
if echo "$out" | grep -q "SCRIPT ERROR"; then echo "script errors during smoke test"; exit 1; fi
echo "all green"
