#!/usr/bin/env bash
# Deploy cleaned static site under nginx and print the working URL.
#
# Usage:
#   SITE=/path/to/work/site DOMAIN=archive.example.com ./scripts/deploy_nginx.sh
#   SITE=/path/to/work/site ./scripts/deploy_nginx.sh          # listen on IP / _
#   WEBROOT=/var/www/ds-forum-archive PORT=80 ...
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
SITE="${SITE:-$DATA_DIR/work/site}"
WEBROOT="${WEBROOT:-/var/www/ds-forum-archive}"
DOMAIN="${DOMAIN:-_}"
LISTEN_PORT="${LISTEN_PORT:-80}"
NGINX_AVAIL="${NGINX_AVAIL:-/etc/nginx/sites-available/ds-forum-archive.conf}"
NGINX_ENABLED="${NGINX_ENABLED:-/etc/nginx/sites-enabled/ds-forum-archive.conf}"
ENTRY="ds-alliance.ru/forum/default.htm"

if [[ ! -f "$SITE/$ENTRY" ]]; then
  echo "ERROR: no $SITE/$ENTRY — set SITE= or run build_site.sh first" >&2
  exit 1
fi

if ! command -v nginx >/dev/null; then
  echo "ERROR: nginx not installed (apt install nginx / dnf install nginx)" >&2
  exit 1
fi

echo "==> Sync $SITE → $WEBROOT"
sudo mkdir -p "$WEBROOT"
sudo rsync -a --delete "$SITE/" "$WEBROOT/"

echo "==> Write nginx site (server_name=$DOMAIN listen=$LISTEN_PORT)"
TMP="$(mktemp)"
sed \
  -e "s|server_name archive.example.com;|server_name ${DOMAIN};|" \
  -e "s|listen 80;|listen ${LISTEN_PORT};|" \
  -e "s|listen \[::\]:80;|listen [::]:${LISTEN_PORT};|" \
  -e "s|root /var/www/ds-forum-archive;|root ${WEBROOT};|" \
  "$REPO_ROOT/nginx/archive.conf" > "$TMP"
sudo cp "$TMP" "$NGINX_AVAIL"
rm -f "$TMP"

# Debian/Ubuntu style; on other distros sites-enabled may be absent
if [[ -d "$(dirname "$NGINX_ENABLED")" ]]; then
  sudo ln -sfn "$NGINX_AVAIL" "$NGINX_ENABLED"
  # avoid default site stealing /
  if [[ -L /etc/nginx/sites-enabled/default ]]; then
    sudo rm -f /etc/nginx/sites-enabled/default
  fi
else
  echo "NOTE: no sites-enabled — ensure $NGINX_AVAIL is included from nginx.conf" >&2
fi

sudo nginx -t
if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  sudo systemctl reload nginx || sudo systemctl restart nginx
else
  sudo nginx -s reload 2>/dev/null || sudo nginx
fi

# Pick URL host for the printed link
if [[ "$DOMAIN" != "_" && "$DOMAIN" != "localhost" ]]; then
  HOST_FOR_URL="$DOMAIN"
else
  HOST_FOR_URL="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$HOST_FOR_URL" ]] || HOST_FOR_URL="127.0.0.1"
fi

if [[ "$LISTEN_PORT" == "80" ]]; then
  BASE="http://${HOST_FOR_URL}"
else
  BASE="http://${HOST_FOR_URL}:${LISTEN_PORT}"
fi
URL="${BASE}/${ENTRY}"

# Local smoke (may fail if firewall; still print URL)
CODE="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://127.0.0.1:${LISTEN_PORT}/${ENTRY}" || true)"

echo
echo "=============================================="
echo "  ARCHIVE READY"
echo "  ${URL}"
echo "=============================================="
if [[ "$CODE" == "200" ]]; then
  echo "  local check: HTTP ${CODE} OK"
else
  echo "  local check: HTTP ${CODE:-n/a} (open the link above from your browser)"
fi
echo
