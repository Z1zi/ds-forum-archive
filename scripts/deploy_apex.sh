#!/usr/bin/env bash
# Put the apex stub on nginx. This is not the forum archive.
#
#   APEX_DOMAIN=example.org ./scripts/deploy_apex.sh
#   APEX_DOMAIN=example.org ARCHIVE_DOMAIN=archive.example.org ./scripts/deploy_apex.sh
#   APEX_ROOT=/var/www/apex-stub LISTEN_PORT=80
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APEX_DOMAIN="${APEX_DOMAIN:?Set APEX_DOMAIN to the apex name, for example example.org}"
ARCHIVE_DOMAIN="${ARCHIVE_DOMAIN:-}"
APEX_ROOT="${APEX_ROOT:-/var/www/apex-stub}"
LISTEN_PORT="${LISTEN_PORT:-80}"
NGINX_AVAIL="${NGINX_AVAIL:-/etc/nginx/sites-available/apex-stub.conf}"
NGINX_ENABLED="${NGINX_ENABLED:-/etc/nginx/sites-enabled/apex-stub.conf}"

if ! command -v nginx >/dev/null; then
  echo "ERROR: nginx not installed" >&2
  exit 1
fi

echo "==> Apex page (APEX_DOMAIN=$APEX_DOMAIN ARCHIVE_DOMAIN=${ARCHIVE_DOMAIN:-none})"
PAGE="$(mktemp)"
python3 - "$REPO_ROOT/nginx/apex-stub.html" "$PAGE" "$APEX_DOMAIN" "$ARCHIVE_DOMAIN" <<'PY'
import sys
src, dst, apex, archive = sys.argv[1:5]
text = open(src, encoding="utf-8").read().replace("example.org", apex)
if archive:
    link = f'<p><a href="https://{archive}/">Архив форума</a></p>'
    text = text.replace("<!-- ARCHIVE_LINK -->", link)
else:
    text = text.replace("    <!-- ARCHIVE_LINK -->\n", "")
open(dst, "w", encoding="utf-8").write(text)
PY
sudo mkdir -p "$APEX_ROOT"
sudo cp "$PAGE" "$APEX_ROOT/index.html"
sudo chmod 644 "$APEX_ROOT/index.html"
rm -f "$PAGE"

echo "==> nginx site (server_name=$APEX_DOMAIN root=$APEX_ROOT)"
CONF="$(mktemp)"
sed \
  -e "s|server_name example.org;|server_name ${APEX_DOMAIN};|" \
  -e "s|listen 80;|listen ${LISTEN_PORT};|" \
  -e "s|listen \[::\]:80;|listen [::]:${LISTEN_PORT};|" \
  -e "s|root /var/www/apex-stub;|root ${APEX_ROOT};|" \
  "$REPO_ROOT/nginx/apex-stub.conf" > "$CONF"
sudo cp "$CONF" "$NGINX_AVAIL"
rm -f "$CONF"

if [[ -d "$(dirname "$NGINX_ENABLED")" ]]; then
  sudo ln -sfn "$NGINX_AVAIL" "$NGINX_ENABLED"
fi

sudo nginx -t
if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  sudo systemctl reload nginx || sudo systemctl restart nginx
else
  sudo nginx -s reload 2>/dev/null || sudo nginx
fi

if [[ "$LISTEN_PORT" == "80" ]]; then
  URL="http://${APEX_DOMAIN}/"
else
  URL="http://${APEX_DOMAIN}:${LISTEN_PORT}/"
fi
echo
echo "=============================================="
echo "  APEX READY"
echo "  ${URL}"
if [[ -n "$ARCHIVE_DOMAIN" ]]; then
  echo "  archive: http://${ARCHIVE_DOMAIN}/"
fi
echo "=============================================="
echo
