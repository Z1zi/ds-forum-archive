#!/usr/bin/env bash
# Pack cleaned site into GitHub Release-friendly chunks (<1900MB each).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
SITE="${SITE:-$DATA_DIR/work/site}"
DIST="${DIST:-$DATA_DIR/work/dist}"
PREFIX="${PREFIX:-ds-forum-static}"

if [[ ! -d "$SITE/ds-alliance.ru" ]]; then
  echo "No cleaned site at $SITE — run clean_static.py first" >&2
  exit 1
fi

command -v zstd >/dev/null || { echo "zstd required" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Creating multi-volume tar.zst (≈1800 MiB volumes) from $SITE"
TMP="$DIST/${PREFIX}.tar"
tar -C "$SITE" -cf "$TMP" .
zstd -T0 -19 -f "$TMP" -o "${TMP}.zst"
rm -f "$TMP"
split -b 1800M -d -a 2 "${TMP}.zst" "$DIST/${PREFIX}.tar.zst.part"
rm -f "${TMP}.zst"

(
  cd "$DIST"
  sha256sum ${PREFIX}.tar.zst.part* > SHA256SUMS
  cat > README-RELEASE.txt <<EOF
Dark Side (EVE) forum static archive — data volumes
===================================================
Concatenate parts, then extract:

  cat ${PREFIX}.tar.zst.part* > ${PREFIX}.tar.zst
  sha256sum -c SHA256SUMS
  zstd -d ${PREFIX}.tar.zst
  sudo mkdir -p /var/www/ds-forum-archive
  sudo tar -xf ${PREFIX}.tar -C /var/www/ds-forum-archive

Document root must contain ds-alliance.ru/ and index.html.
See repository README for nginx setup.
EOF
)

echo "==> Artifacts:"
ls -lh "$DIST"
