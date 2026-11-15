#!/usr/bin/env python3
"""Installs the strip reader outside any git checkout, as an addon is installed: copies the
files the reader runs from into one folder, with a VERSION file that names the commit. A
program that serves the game starts the reader from that folder, so a checkout or a branch
switch in a repo never changes the reader it runs next (#117).

    python3 tools/install_reader.py [--to <dir>]

The default folder is ~/Library/Application Support/HelloLink/reader. Restart the reader
after an install, when nobody plays. Exit 1, with nothing changed, when a reader file differs
from the commit (VERSION would not be true)."""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FILES = ("hellolink_strip.py", "strip1.py", "strip_api.py", "hellolink.py", "strip_capture.swift")
DEFAULT = Path.home() / "Library" / "Application Support" / "HelloLink" / "reader"


def git(*args):
    return subprocess.run(["git", "-C", str(HERE), *args], capture_output=True, text=True, check=True).stdout.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--to", type=Path, default=DEFAULT, help="the folder to install into (default: %(default)s)")
    to = ap.parse_args(argv).to.expanduser().resolve()
    changed = git("status", "--porcelain", "--", *FILES)
    if changed:
        print("install_reader: these reader files differ from the commit; commit or restore them first:\n" + changed,
              file=sys.stderr)
        return 1
    commit = git("rev-parse", "HEAD")
    to.parent.mkdir(parents=True, exist_ok=True)
    new = Path(tempfile.mkdtemp(prefix=".reader-new-", dir=to.parent))
    for name in FILES:
        # shutil.copy, not copy2: a new mtime makes the reader rebuild the capture tool from
        # this strip_capture.swift (capture_tool() compares the times).
        shutil.copy(HERE / name, new / name)
    (new / "VERSION").write_text(commit + "\n")
    if to.exists():
        old = Path(tempfile.mkdtemp(prefix=".reader-old-", dir=to.parent))
        to.rename(old / "reader")
        new.rename(to)
        shutil.rmtree(old)
    else:
        new.rename(to)
    print("install_reader: %s installed in %s; restart the reader to run it" % (commit[:7], to))
    return 0


if __name__ == "__main__":
    sys.exit(main())
