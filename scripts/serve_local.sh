#!/usr/bin/env bash
# Smoke-test cleaned site locally (no nginx required).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
SITE="${SITE:-$DATA_DIR/work/site}"
PORT="${PORT:-8765}"

if [[ ! -f "$SITE/ds-alliance.ru/forum/default.htm" ]]; then
  echo "Missing $SITE/ds-alliance.ru/forum/default.htm — build site first" >&2
  exit 1
fi

cd "$SITE"
echo "Serving $SITE on http://127.0.0.1:${PORT}/"
echo "Try:  http://127.0.0.1:${PORT}/ds-alliance.ru/forum/default.htm"
echo "Ctrl+C to stop"

exec python3 - "$PORT" <<'PY'
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import mimetypes, os, sys

port = int(sys.argv[1])
mimetypes.add_type("text/html; charset=windows-1251", ".htm")
mimetypes.add_type("text/css", ".css")

class H(SimpleHTTPRequestHandler):
    def guess_type(self, path):
        name = os.path.basename(path)
        if name.startswith("index.php") or name.startswith("@"):
            return "text/html; charset=windows-1251"
        return super().guess_type(path)

print(f"listening on 127.0.0.1:{port}", flush=True)
ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PY
