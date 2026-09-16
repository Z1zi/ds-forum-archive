#!/usr/bin/env bash
# Download private Release data, unpack to WEBROOT, optionally deploy nginx.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${TAG:-v1.0.0}"
REPO="${REPO:-Z1zi/ds-forum-archive}"
DIST="${DIST:-$REPO_ROOT/../work/dist-download}"
WEBROOT="${WEBROOT:-/var/www/ds-forum-archive}"
DOMAIN="${DOMAIN:-_}"
DEPLOY_NGINX="${DEPLOY_NGINX:-1}"
ENTRY="ds-alliance.ru/forum/default.htm"

command -v gh >/dev/null || { echo "need gh (GitHub CLI)" >&2; exit 1; }
command -v zstd >/dev/null || { echo "need zstd" >&2; exit 1; }

mkdir -p "$DIST"
echo "==> gh release download $TAG from $REPO"
gh release download "$TAG" -R "$REPO" -D "$DIST" --clobber

cd "$DIST"
cat ds-forum-static.tar.zst.part* > ds-forum-static.tar.zst
sha256sum -c SHA256SUMS
zstd -d -f ds-forum-static.tar.zst
sudo mkdir -p "$WEBROOT"
sudo tar -xf ds-forum-static.tar -C "$WEBROOT"
test -f "$WEBROOT/$ENTRY"

if [[ "$DEPLOY_NGINX" == "1" ]]; then
  SITE="$WEBROOT" DOMAIN="$DOMAIN" WEBROOT="$WEBROOT" \
    "$REPO_ROOT/scripts/deploy_nginx.sh"
else
  HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$HOST" ]] || HOST="127.0.0.1"
  echo
  echo "=============================================="
  echo "  DATA UNPACKED to $WEBROOT"
  echo "  Next: SITE=$WEBROOT DOMAIN=your.host ./scripts/deploy_nginx.sh"
  echo "  Entry file: $WEBROOT/$ENTRY"
  echo "=============================================="
fi
