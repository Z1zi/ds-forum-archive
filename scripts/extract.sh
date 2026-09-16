#!/usr/bin/env bash
# Extract Offline Explorer download tree from local archives into work/raw/
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Data lives next to the clone by default (parent of repo), override with DATA_DIR
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
OUT="${OUT:-$DATA_DIR/work/raw}"
mkdir -p "$OUT"

RAR="$DATA_DIR/DarkSide_forum-001.rar"
if [[ ! -f "$RAR" ]]; then
  # also accept rar inside repo (discouraged)
  RAR="$REPO_ROOT/DarkSide_forum-001.rar"
fi
if [[ ! -f "$RAR" ]]; then
  echo "Missing DarkSide_forum-001.rar — set DATA_DIR to the folder that contains it" >&2
  exit 1
fi

echo "==> Extracting RAR download tree to $OUT"
unrar x -o+ "$RAR" 'Offline Explorer/download/' "$OUT/"

shopt -s nullglob
for z in "$DATA_DIR"/drive-download-*.zip; do
  echo "==> Merging $z (forum paths only, non-clobber)"
  unzip -n "$z" 'Offline Explorer/download/ds-alliance.ru/*' -d "$OUT/" || true
  unzip -n "$z" 'ds-alliance.ru/*' -d "$OUT/Offline Explorer/download/" || true
done

echo "Done. Source tree:"
du -sh "$OUT/Offline Explorer/download" 2>/dev/null || du -sh "$OUT"
