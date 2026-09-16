#!/usr/bin/env bash
# Smoke-test cleaned site locally (no nginx required).
# Prints a ready URL and exits non-zero if entry page is missing.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
SITE="${SITE:-$DATA_DIR/work/site}"
PORT="${PORT:-8765}"
BIND="${BIND:-127.0.0.1}"
ENTRY="ds-alliance.ru/forum/default.htm"

if [[ ! -f "$SITE/$ENTRY" ]]; then
  echo "Missing $SITE/$ENTRY — build site first (./scripts/build_site.sh)" >&2
  exit 1
fi

URL="http://${BIND}:${PORT}/${ENTRY}"
if [[ "$BIND" == "0.0.0.0" ]]; then
  LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$LAN_IP" ]] || LAN_IP="127.0.0.1"
  URL="http://${LAN_IP}:${PORT}/${ENTRY}"
fi

cd "$SITE"

echo "Serving $SITE (bind ${BIND}:${PORT})"
echo
echo "=============================================="
echo "  ARCHIVE READY"
echo "  ${URL}"
echo "=============================================="
echo "Ctrl+C to stop"
echo

exec python3 - "$PORT" "$BIND" <<'PY'
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import mimetypes, os, sys

port = int(sys.argv[1])
bind = sys.argv[2]
mimetypes.add_type("text/html; charset=windows-1251", ".htm")
mimetypes.add_type("text/css", ".css")

class H(SimpleHTTPRequestHandler):
    def guess_type(self, path):
        name = os.path.basename(path)
        if name.startswith("index.php") or name.startswith("@"):
            return "text/html; charset=windows-1251"
        return super().guess_type(path)

ThreadingHTTPServer((bind, port), H).serve_forever()
PY
