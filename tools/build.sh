#!/usr/bin/env bash
# Export Road to sudo for Linux and Windows, then zip each build for release.
#   GODOT=/path/to/godot tools/build.sh [version]
# Requires the Godot 4.4.1 export templates to be installed.
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="build"
rm -rf "$OUT"
mkdir -p "$OUT/linux" "$OUT/windows" "$OUT/dist"

# Build the import cache first so a fresh checkout exports cleanly.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "== exporting Linux"
"$GODOT" --headless --path . --export-release "Linux" "$OUT/linux/RoadToSudo.x86_64"
chmod +x "$OUT/linux/RoadToSudo.x86_64"

echo "== exporting Windows"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/windows/RoadToSudo.exe"

# Package: a README next to each binary, then a zip per platform.
cp README.md "$OUT/linux/README.md" 2>/dev/null || true
cp README.md "$OUT/windows/README.md" 2>/dev/null || true
printf 'Road to sudo\n\nRun ./RoadToSudo.x86_64 (you may need: chmod +x RoadToSudo.x86_64).\n' > "$OUT/linux/HOW-TO-RUN.txt"
printf 'Road to sudo\n\nRun RoadToSudo.exe. Windows SmartScreen may warn about an unsigned app; choose "Run anyway".\n' > "$OUT/windows/HOW-TO-RUN.txt"

( cd "$OUT/linux"   && zip -q -r "../dist/RoadToSudo-${VERSION}-linux-x86_64.zip" . )
( cd "$OUT/windows" && zip -q -r "../dist/RoadToSudo-${VERSION}-windows-x86_64.zip" . )

echo "== done"
ls -lh "$OUT/dist"
