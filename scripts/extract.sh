#!/usr/bin/env bash
# Prepare Offline Explorer download tree from Google Drive dumps.
#
# Canonical source folder:
#   https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy
#
# Expected items in DATA_DIR (any subset that yields a download tree):
#   DarkSide_forum.rar          # or DarkSide_forum-001.rar (WinRAR volume name)
#   Offline Explorer/           # already unpacked OE project
#   ds-alliance.ru/             # optional host tree next to OE on Drive
#   drive-download-*.zip        # Drive “Download” of folders as ZIP
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
OUT="${OUT:-$DATA_DIR/work/raw}"
DOWNLOAD="$OUT/Offline Explorer/download"

mkdir -p "$OUT"

find_rar() {
  local c
  for c in \
    "$DATA_DIR/DarkSide_forum.rar" \
    "$DATA_DIR/DarkSide_forum-001.rar" \
    "$REPO_ROOT/DarkSide_forum.rar" \
    "$REPO_ROOT/DarkSide_forum-001.rar"
  do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

link_or_copy_tree() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" ]]; then
    echo "  keep existing $dst"
    return 0
  fi
  # Prefer hardlink/copy via cp -a; bind via symlink for speed when same FS
  ln -s "$(cd "$src" && pwd)" "$dst" 2>/dev/null || cp -a "$src" "$dst"
}

echo "==> DATA_DIR=$DATA_DIR"
echo "==> OUT=$OUT"

# 1) Already-extracted Offline Explorer from Drive
if [[ -d "$DATA_DIR/Offline Explorer/download" ]]; then
  echo "==> Using pre-extracted Offline Explorer/download"
  mkdir -p "$OUT/Offline Explorer"
  link_or_copy_tree "$DATA_DIR/Offline Explorer/download" "$DOWNLOAD"
elif [[ -d "$DATA_DIR/Offline Explorer" ]]; then
  echo "==> Found Offline Explorer/ (looking for download/)"
  if [[ -d "$DATA_DIR/Offline Explorer/download" ]]; then
    link_or_copy_tree "$DATA_DIR/Offline Explorer/download" "$DOWNLOAD"
  else
    # OE project may nest as Offline Explorer/Offline Explorer/download
    nested="$(find "$DATA_DIR/Offline Explorer" -type d -name download -print -quit || true)"
    if [[ -n "${nested:-}" ]]; then
      echo "==> Using nested $nested"
      mkdir -p "$OUT/Offline Explorer"
      link_or_copy_tree "$nested" "$DOWNLOAD"
    fi
  fi
fi

# 2) Top-level ds-alliance.ru folder from Drive (merge into download tree)
if [[ -d "$DATA_DIR/ds-alliance.ru" ]]; then
  echo "==> Merging Drive folder ds-alliance.ru into download tree"
  mkdir -p "$DOWNLOAD"
  if [[ -e "$DOWNLOAD/ds-alliance.ru" ]]; then
    # overlay without clobbering newer OE copies
    rsync -a --ignore-existing "$DATA_DIR/ds-alliance.ru/" "$DOWNLOAD/ds-alliance.ru/" 2>/dev/null \
      || cp -an "$DATA_DIR/ds-alliance.ru/." "$DOWNLOAD/ds-alliance.ru/" 2>/dev/null \
      || true
  else
    link_or_copy_tree "$DATA_DIR/ds-alliance.ru" "$DOWNLOAD/ds-alliance.ru"
  fi
fi

# 3) RAR if download tree still incomplete
if [[ ! -d "$DOWNLOAD/ds-alliance.ru" ]]; then
  if RAR="$(find_rar)"; then
    echo "==> Extracting $RAR → $OUT"
    unrar x -o+ "$RAR" 'Offline Explorer/download/' "$OUT/"
  else
    echo "ERROR: no Offline Explorer/download and no DarkSide_forum.rar in $DATA_DIR" >&2
    echo "Download from: https://drive.google.com/drive/folders/1vu788RsUnWlqY_wzHBs2DaGKrJAve1Gy" >&2
    exit 1
  fi
else
  echo "==> download/ds-alliance.ru already present — skip RAR (set FORCE_RAR=1 to extract anyway)"
  if [[ "${FORCE_RAR:-0}" == "1" ]] && RAR="$(find_rar)"; then
    echo "==> FORCE_RAR: extracting $RAR"
    unrar x -o+ "$RAR" 'Offline Explorer/download/' "$OUT/"
  fi
fi

# 4) Optional Drive ZIP fragments (folder downloads)
# Skip by default if forum tree already present (ZIPs are mostly noisy OE duplicates).
if [[ "${MERGE_DRIVE_ZIP:-0}" == "1" ]]; then
  shopt -s nullglob
  for z in "$DATA_DIR"/drive-download-*.zip; do
    echo "==> Merging $z (non-clobber)"
    unzip -n "$z" 'Offline Explorer/download/*' -d "$OUT/" 2>/dev/null || true
    unzip -n "$z" 'ds-alliance.ru/*' -d "$DOWNLOAD/" 2>/dev/null || true
  done
else
  echo "==> Skip drive-download-*.zip (set MERGE_DRIVE_ZIP=1 to merge)"
fi

if [[ ! -d "$DOWNLOAD/ds-alliance.ru" ]]; then
  echo "ERROR: still no $DOWNLOAD/ds-alliance.ru" >&2
  exit 1
fi

echo "Done:"
du -sh "$DOWNLOAD" "$DOWNLOAD/ds-alliance.ru" 2>/dev/null || true
