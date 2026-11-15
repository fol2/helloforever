#!/usr/bin/env python3
"""Installs the strip reader outside any git checkout, as an addon is installed: copies the
files the reader runs from into one folder, with a VERSION file that names the commit. A
program that serves the game starts the reader from that folder, by its full path, so a
checkout or a branch switch in a repo never changes the reader it runs next (#117).

    python3 tools/install_reader.py [--to <dir>]

The default folder is ~/Library/Application Support/HelloLink/reader. Stop the reader first,
install, then start it again, when nobody plays. Exit 1, with nothing changed, when:
- a reader file differs from the commit, or the commit lacks it (VERSION would not be true);
- the folder holds anything but an earlier install (it may be a checkout or other files);
- a reader runs from the folder (it imports some modules late, and would mix two versions)."""
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
    return subprocess.run(["git", "-C", str(HERE), *args], capture_output=True, check=True).stdout


def is_install(to):
    """True when `to` holds an earlier install and nothing else: each reader file and VERSION
    as a plain file, and at most a __pycache__ folder of plain .pyc files (Python writes it
    when the reader runs)."""
    if not to.is_dir() or to.is_symlink():
        return False
    want = set(FILES) | {"VERSION"}
    for p in to.iterdir():
        if p.name in want:
            if not plain(p):
                return False
        elif p.name == "__pycache__" and p.is_dir() and not p.is_symlink():
            if not all(plain(q) and q.suffix == ".pyc" for q in p.iterdir()):
                return False
        else:
            return False
    return all((to / name).exists() for name in want)


def plain(p):
    return p.is_file() and not p.is_symlink()


def refusal(to):
    """Why the install must not go into `to`, or None."""
    if to.exists() and not is_install(to):
        return "%s is not an earlier reader install (it holds other things); give another --to" % to
    try:
        runs = subprocess.run(["ps", "-axo", "pid=,args="], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        return "cannot list the processes to see if a reader runs from %s (%s)" % (to, e)
    mine = [line.strip() for line in runs.splitlines() if str(to / "hellolink_strip.py") in line]
    if mine:
        return "a reader runs from %s; stop it first:\n%s" % (to, "\n".join(mine))
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--to", type=Path, default=DEFAULT, help="the folder to install into (default: %(default)s)")
    to = ap.parse_args(argv).to.expanduser().resolve()
    why = refusal(to)
    if why:
        print("install_reader: " + why, file=sys.stderr)
        return 1
    commit = git("rev-parse", "HEAD").decode().strip()
    to.parent.mkdir(parents=True, exist_ok=True)
    new = Path(tempfile.mkdtemp(prefix=".reader-new-", dir=to.parent))
    try:
        for name in FILES:
            data = (HERE / name).read_bytes()
            try:
                committed = git("show", "%s:./%s" % (commit, name))
            except subprocess.CalledProcessError:
                committed = None
            if data != committed:
                print("install_reader: tools/%s differs from %s, or it lacks the file; commit or restore it first"
                      % (name, commit[:7]), file=sys.stderr)
                return 1
            # A new file, so a new mtime: the reader then rebuilds the capture tool from this
            # strip_capture.swift (capture_tool() compares the times).
            (new / name).write_bytes(data)
        (new / "VERSION").write_text(commit + "\n")
        if to.exists():
            old = Path(tempfile.mkdtemp(prefix=".reader-old-", dir=to.parent)) / "reader"
            to.rename(old)
            try:
                new.rename(to)
            except OSError:
                old.rename(to)
                raise
            shutil.rmtree(old.parent)
        else:
            new.rename(to)
    finally:
        if new.exists():
            shutil.rmtree(new)
    print("install_reader: %s installed in %s; start the reader from there" % (commit[:7], to))
    return 0


if __name__ == "__main__":
    sys.exit(main())
