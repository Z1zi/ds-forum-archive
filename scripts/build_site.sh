#!/usr/bin/env bash
# One-shot: clean already-extracted raw tree (or run extract first).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
SRC="${SRC:-$DATA_DIR/work/raw/Offline Explorer/download}"
DST="${DST:-$DATA_DIR/work/site}"
STATS="${STATS:-$DATA_DIR/work/site-stats.json}"

if [[ ! -d "$SRC/ds-alliance.ru" ]]; then
  echo "Source $SRC missing — run ./scripts/extract.sh first or set SRC=" >&2
  exit 1
fi

python3 "$REPO_ROOT/scripts/clean_static.py" --src "$SRC" --dst "$DST" --stats "$STATS"
echo "Site ready at $DST"
