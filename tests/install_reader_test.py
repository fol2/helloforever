#!/usr/bin/env python3
"""The reader installs outside any git checkout (#117): the installed folder holds the reader's
files and the commit, the reader imports from that folder alone, a second install leaves
nothing of the first, and a reader file that differs from the commit stops the install.
Usage: python3 tests/install_reader_test.py"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "tools"
INSTALL = TOOLS / "install_reader.py"
FILES = ("hellolink_strip.py", "strip1.py", "strip_api.py", "hellolink.py", "strip_capture.swift")
tmp = Path(tempfile.mkdtemp(prefix="install-reader-")).resolve()
failed, checks = 0, 0


def check(name, ok, detail=""):
    global failed, checks
    checks += 1
    if not ok:
        failed += 1
        print("FAIL %s %s" % (name, detail))


def run(*args, cwd=None):
    return subprocess.run([sys.executable, *args], capture_output=True, text=True, cwd=cwd)


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


# 1. An install from this checkout: the files, VERSION, and imports from that folder alone.
to = tmp / "Support" / "reader"
done = run(str(INSTALL), "--to", str(to))
check("install exits 0", done.returncode == 0, done.stderr)
for name in FILES:
    check("%s installed and equal" % name, (to / name).is_file() and (to / name).read_bytes() == (TOOLS / name).read_bytes())
head = git(TOOLS, "rev-parse", "HEAD")
check("VERSION names the commit", (to / "VERSION").is_file() and (to / "VERSION").read_text().strip() == head)
probe = ("import sys; sys.path.insert(0, %r); import hellolink_strip, strip1, strip_api, hellolink; "
         "print(hellolink_strip.CAPTURE_SOURCE)" % str(to))
imp = run("-I", "-c", probe, cwd=tmp)
check("the installed reader imports from its folder alone", imp.returncode == 0, imp.stderr[-300:])
check("the capture source is the installed one", imp.stdout.strip() == str(to / "strip_capture.swift"), imp.stdout)
helped = run("-I", str(to / "hellolink_strip.py"), "--help", cwd=tmp)
check("the installed reader runs", helped.returncode == 0 and "watch" in helped.stdout, helped.stderr[-300:])

# 2. A second install replaces the first and leaves none of it.
to.mkdir(parents=True, exist_ok=True)
(to / "left-over.py").write_text("# from an older install\n")
again = run(str(INSTALL), "--to", str(to))
check("second install exits 0", again.returncode == 0, again.stderr)
check("nothing of the first install is left", not (to / "left-over.py").exists())
check("no temporary folder is left", sorted(p.name for p in to.parent.iterdir()) == ["reader"],
      str(list(to.parent.iterdir())))

# 3. A reader file that differs from the commit stops the install, and nothing changes.
repo = tmp / "repo"
(repo / "tools").mkdir(parents=True)
for name in FILES + ("install_reader.py",):
    shutil.copy(TOOLS / name, repo / "tools" / name)
git(repo, "init", "-q")
git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "add", ".")
git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "reader")
with open(repo / "tools" / "strip1.py", "a") as f:
    f.write("# not committed\n")
before = (to / "VERSION").read_text() if (to / "VERSION").exists() else None
dirty = run(str(repo / "tools" / "install_reader.py"), "--to", str(to))
check("a changed reader file stops the install", dirty.returncode == 1 and "strip1.py" in dirty.stderr,
      "exit %d %s" % (dirty.returncode, dirty.stderr))
check("the installed reader is unchanged", (to / "VERSION").read_text() == before
      and (to / "strip1.py").read_bytes() == (TOOLS / "strip1.py").read_bytes())

shutil.rmtree(tmp)
print("== %d checks, %d failed" % (checks, failed))
sys.exit(1 if failed else 0)
