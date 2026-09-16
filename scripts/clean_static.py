#!/usr/bin/env python3
"""Build a nginx-ready static mirror from an Offline Explorer dump of SMF.

Keeps the OE host layout so relative links like ../../i.imgur.com/... keep working.
Drops session/wap/markasread noise, OE metadata, and credential-bearing URLs.
Resolves %&Ovr / _&Ovr overwrite folders (newer copy wins).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

# OE metadata / junk
SKIP_NAME_EXACT = {
    "Descr.WD3",
    "Thumbs.db",
    ".DS_Store",
    "desktop.ini",
}
SKIP_SUFFIXES = (
    ".wd3",
    ".mpx",
    ".tmp",
    ".lck",
)

# Filename / path noise for SMF mirror pages
DROP_IF_CONTAINS = (
    "action=markasread",
    "action=emailuser",
    "action=collapse",
    "action=login",
    "action=login2",
    "action=logout",
    "action=post",
    "action=pm",
    "action=profile;area=account",
    "action=admin",
    "hash_passwrd=",
    "passwrd=",
    ";wap",
    "_wap",
    ";wap2",
    "_wap2",
    ";nowap",
    "_nowap",
    "prev_next=",
    "PHPSESSID",
)

# Session-like query fragments OE baked into filenames
SESSION_KEYS = re.compile(
    r"(?:^|[;_&@])(?:[a-f0-9]{7,10}|ceba10063e|ed9305c|c73c5bd|ea216504a)=[a-f0-9]{16,40}",
    re.I,
)

OVR_DIR = re.compile(r"^(?:%&Ovr|_&Ovr|&Ovr)\d+$")
FIN_SUFFIX = re.compile(r"@fin\d+$")
HTML_ASSET = re.compile(r"\.(?:html?|css|js|xml|txt)$", re.I)

# Prefer canonical SMF content pages
KEEP_ACTIONS = {
    "credits",
    "help",
    "printpage",
    "reporttm",
}


@dataclass
class Stats:
    scanned: int = 0
    copied: int = 0
    skipped_noise: int = 0
    skipped_ovr_loser: int = 0
    skipped_dup: int = 0
    rewritten_html: int = 0
    bytes_in: int = 0
    bytes_out: int = 0
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "scanned": self.scanned,
            "copied": self.copied,
            "skipped_noise": self.skipped_noise,
            "skipped_ovr_loser": self.skipped_ovr_loser,
            "skipped_dup": self.skipped_dup,
            "rewritten_html": self.rewritten_html,
            "bytes_in": self.bytes_in,
            "bytes_out": self.bytes_out,
            "notes": self.notes,
        }


def is_noise_filename(name: str) -> bool:
    lower = name.lower()
    if name in SKIP_NAME_EXACT or lower in {s.lower() for s in SKIP_NAME_EXACT}:
        return True
    if any(lower.endswith(suf) for suf in SKIP_SUFFIXES):
        return True
    for frag in DROP_IF_CONTAINS:
        if frag.lower() in lower:
            return True
    # bare session cookies in names
    if SESSION_KEYS.search(name):
        # keep if it's otherwise a real topic/board page? No — sessionized dupes.
        return True
    return False


def strip_ovr_parts(rel: Path) -> Path:
    """Remove OE overwrite directory components from a relative path."""
    parts = [p for p in rel.parts if not OVR_DIR.match(p)]
    return Path(*parts) if parts else Path(".")


def normalize_asset_name(name: str) -> str:
    """index.css@fin20 -> index.css; foo+bar.jpg stays (nginx can serve +)."""
    name = FIN_SUFFIX.sub("", name)
    # OE sometimes saved URL-encoded spaces as +
    return name


def content_priority(rel: Path) -> tuple:
    """Higher is better when several sources map to the same destination."""
    name = rel.name
    score = 0
    # Prefer non-Ovr paths slightly less than Ovr (Ovr = later download)
    if any(OVR_DIR.match(p) for p in rel.parts):
        score += 100
    # Prefer real topic/board pages over msg-deep-links
    if re.search(r"topic=\d+\.\d+$", name):
        score += 50
    if re.search(r"board=\d+\.\d+$", name):
        score += 50
    if ".msg" in name:
        score += 10
    if "topicseen" in name:
        score -= 20
    if "sort=" in name:
        score -= 30
    if name.endswith(".html"):
        score -= 5
    # larger files usually more complete — handled separately via size
    return (score, len(name))


def iter_files(root: Path) -> Iterable[Path]:
    for dirpath, dirnames, filenames in os.walk(root):
        # prune OE control dirs if present
        dirnames[:] = [d for d in dirnames if d not in {"Offline Explorer", "Queue", "RMV"}]
        for fn in filenames:
            yield Path(dirpath) / fn


def should_rewrite(path: Path) -> bool:
    name = path.name
    if HTML_ASSET.search(name):
        return True
    # OE SMF pages: index.php@topic=10.0 — pathlib suffix is ".0", not ""
    if name.startswith("index.php") or name in {"default.htm", "default.html"}:
        return True
    if name.endswith((".htm", ".html", ".css", ".js")):
        return True
    return False


def rewrite_text(data: bytes) -> tuple[bytes, bool]:
    """Light touch rewrites inside HTML/CSS/JS."""
    # Detect charset; OE SMF dump is mostly windows-1251 / binary-safe enough as latin1 pass-through
    try:
        text = data.decode("cp1251")
        enc = "cp1251"
    except UnicodeDecodeError:
        try:
            text = data.decode("utf-8")
            enc = "utf-8"
        except UnicodeDecodeError:
            return data, False

    original = text

    # Themes/...@fin20 -> Themes/...
    text = re.sub(r"(Themes/[^\"'\s]+?)@fin\d+", r"\1", text)
    text = re.sub(r"(scripts/[^\"'\s]+?)@fin\d+", r"\1", text)

    # Drop SMF session tokens baked into OE filenames inside links
    text = re.sub(
        r"(index\.php@[^\s\"']*?);(?:[a-f0-9]{7,10}|ceba10063e|ed9305c|c73c5bd|ea216504a)=[a-f0-9]{16,40}",
        r"\1",
        text,
        flags=re.I,
    )

    # Broken OE https embeds: ../../https@github.com/... -> https://github.com/...
    text = re.sub(
        r"(?:(?:\.\./)+)https@([A-Za-z0-9.-]+(/[^\"'\s]*)?)",
        r"https://\1",
        text,
    )
    text = re.sub(r"https@([A-Za-z0-9.-]+)", r"https://\1", text)
    text = re.sub(r"http@([A-Za-z0-9.-]+)", r"http://\1", text)

    # Soft-disable live forms / login POSTs in archive (keep markup, kill action)
    text = re.sub(
        r'(<form\b[^>]*\baction=["\'][^"\']*action=login2[^"\']*["\'])',
        r'\1 data-archive-disabled="1"',
        text,
        flags=re.I,
    )

    if text == original:
        return data, False
    return text.encode(enc, errors="replace"), True


def copy_file(src: Path, dst: Path, stats: Stats, rewrite: bool) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    size = src.stat().st_size
    stats.bytes_in += size
    if rewrite and should_rewrite(src):
        data = src.read_bytes()
        out, changed = rewrite_text(data)
        dst.write_bytes(out)
        if changed:
            stats.rewritten_html += 1
        stats.bytes_out += len(out)
    else:
        shutil.copy2(src, dst, follow_symlinks=True)
        stats.bytes_out += size
    stats.copied += 1


def build(src_root: Path, dst_root: Path, include_external: bool) -> Stats:
    stats = Stats()
    forum_prefix = Path("ds-alliance.ru") / "forum"

    # First pass: choose winners for each destination relative path
    winners: dict[Path, tuple[tuple, int, Path]] = {}
    # dest -> (priority, size, src)

    for src in iter_files(src_root):
        stats.scanned += 1
        rel = src.relative_to(src_root)

        if is_noise_filename(src.name) or any(is_noise_filename(p) for p in rel.parts):
            stats.skipped_noise += 1
            continue

        # Optional: only forum + assets referenced under download/
        if not include_external:
            if rel.parts[:2] != ("ds-alliance.ru", "forum") and rel.parts[:1] != ("ds-alliance.ru",):
                # allow kb.ds-alliance.com etc. only if include_external
                if not str(rel).startswith("ds-alliance.ru"):
                    stats.skipped_noise += 1
                    continue

        dest_rel = strip_ovr_parts(rel)
        dest_name = normalize_asset_name(dest_rel.name)
        dest_rel = dest_rel.with_name(dest_name) if dest_rel.name else dest_rel

        # Directory named index.php (OE empty) — skip
        if src.is_dir():
            continue

        try:
            size = src.stat().st_size
        except OSError:
            continue

        # Skip tiny error stubs (<200B) that OE saved for markasread-like empties
        # but allow small icons
        if size < 180 and ("index.php@" in src.name or src.name.endswith(".html")):
            stats.skipped_noise += 1
            continue

        pr = content_priority(rel)
        key = dest_rel
        prev = winners.get(key)
        if prev is None:
            winners[key] = (pr, size, src)
        else:
            prev_pr, prev_size, prev_src = prev
            # Ovr / higher priority wins; tie-break larger file
            if pr > prev_pr or (pr == prev_pr and size >= prev_size):
                winners[key] = (pr, size, src)
                stats.skipped_ovr_loser += 1
            else:
                stats.skipped_ovr_loser += 1

    if dst_root.exists():
        shutil.rmtree(dst_root)
    dst_root.mkdir(parents=True)

    for dest_rel, (_pr, _size, src) in winners.items():
        dst = dst_root / dest_rel
        # Avoid copying credential-ish paths that slipped through
        if "hash_passwrd=" in str(dest_rel) or "passwrd=" in str(dest_rel):
            stats.skipped_noise += 1
            continue
        rewrite = str(dest_rel).startswith(str(forum_prefix))
        copy_file(src, dst, stats, rewrite=rewrite)

    forum_dir = dst_root / forum_prefix
    forum_dir.mkdir(parents=True, exist_ok=True)
    boards = sorted(forum_dir.glob("index.php@board=*.0"))
    topics_sample = list(forum_dir.glob("index.php@topic=*.0"))
    has_default = (forum_dir / "default.htm").is_file()

    # Prefer original SMF board index saved as default.htm
    forum_entry = "default.htm" if has_default else "archive-index.html"

    toc = forum_dir / "archive-index.html"
    links = []
    for b in boards:
        m = re.search(r"board=(\d+)\.0$", b.name)
        if m:
            links.append(f'<li><a href="{b.name}">Board {m.group(1)}</a></li>')
    toc.write_text(
        "<!DOCTYPE html><html lang='ru'><head><meta charset='utf-8'>"
        "<title>DS Archive — оглавление</title></head><body>"
        "<h1>Архив форума Dark Side</h1>"
        "<p>Срез Offline Explorer, апрель 2014. Движок оригинала: SMF 2.0.4.</p>"
        f"<p><a href='{forum_entry}'>Главная (как в оригинале)</a> · "
        f"бордов *.0: {len(boards)}, топиков *.0: {len(topics_sample)}</p>"
        "<h2>Разделы (board=N.0)</h2><ul>\n"
        + "\n".join(links)
        + "\n</ul></body></html>\n",
        encoding="utf-8",
    )

    (forum_dir / "index.html").write_text(
        "<!DOCTYPE html><html lang='ru'><head><meta charset='utf-8'>"
        f"<meta http-equiv='refresh' content='0; url={forum_entry}' />"
        "<title>DS Archive</title></head>"
        f"<body><a href='{forum_entry}'>Открыть архив</a> · "
        "<a href='archive-index.html'>Оглавление</a></body></html>\n",
        encoding="utf-8",
    )

    (dst_root / "index.html").write_text(
        "<!DOCTYPE html><html lang='ru'><head><meta charset='utf-8' />"
        f"<meta http-equiv='refresh' content='0; url=ds-alliance.ru/forum/{forum_entry}' />"
        "<title>Dark Side forum archive</title>"
        f"<link rel='canonical' href='ds-alliance.ru/forum/{forum_entry}' />"
        "</head><body>"
        f"<p><a href='ds-alliance.ru/forum/{forum_entry}'>"
        "Открыть архив форума Dark Side (SMF 2.0.4, срез 2014)</a></p>"
        "</body></html>\n",
        encoding="utf-8",
    )

    stats.notes.append(f"boards_with_page0={len(boards)}")
    stats.notes.append(f"topics_with_page0={len(topics_sample)}")
    stats.notes.append(f"forum_entry={forum_entry}")
    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--src",
        type=Path,
        required=True,
        help="Path to Offline Explorer/download/ (hosts as top-level dirs)",
    )
    ap.add_argument("--dst", type=Path, required=True, help="Output site root")
    ap.add_argument(
        "--forum-only",
        action="store_true",
        help="Copy only ds-alliance.ru (no external image hosts)",
    )
    ap.add_argument("--stats", type=Path, help="Write JSON stats")
    args = ap.parse_args()

    src = args.src
    if (src / "Offline Explorer" / "download").is_dir():
        src = src / "Offline Explorer" / "download"
    elif (src / "download").is_dir() and (src / "download" / "ds-alliance.ru").exists():
        src = src / "download"

    if not (src / "ds-alliance.ru").exists():
        print(f"ERROR: ds-alliance.ru not found under {src}", file=sys.stderr)
        return 1

    stats = build(src, args.dst, include_external=not args.forum_only)
    print(json.dumps(stats.to_dict(), ensure_ascii=False, indent=2))
    if args.stats:
        args.stats.parent.mkdir(parents=True, exist_ok=True)
        args.stats.write_text(json.dumps(stats.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
