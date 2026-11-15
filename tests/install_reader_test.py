#!/usr/bin/env python3
"""The reader installs outside any git checkout (#117): the installed folder holds the reader's
files and the commit, the reader imports from that folder alone, a second install leaves
nothing of the first, the copied capture source is newer than the commit's (so the reader
rebuilds the capture tool), and the install refuses, changing nothing, when a reader file
differs from the commit, when the folder holds other things, or when a reader runs from it.
Usage: python3 tests/install_reader_test.py"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "tools"
INSTALL = TOOLS / "install_reader.py"
FILES = ("hellolink_strip.py", "strip1.py", "strip_api.py", "hellolink.py", "strip_capture.swift", "assistant.py")
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
probe = ("import sys; sys.path.insert(0, %r); import hellolink_strip, strip1, strip_api, hellolink, assistant; "
         "print(hellolink_strip.CAPTURE_SOURCE)" % str(to))
imp = run("-I", "-c", probe, cwd=tmp)
check("the installed reader imports from its folder alone", imp.returncode == 0, imp.stderr[-300:])
check("the capture source is the installed one", imp.stdout.strip() == str(to / "strip_capture.swift"), imp.stdout)
helped = run("-I", str(to / "hellolink_strip.py"), "--help", cwd=tmp)
check("the installed reader runs", helped.returncode == 0 and "watch" in helped.stdout, helped.stderr[-300:])

# 2. A second install replaces the first and leaves none of it.
stale = to / "__pycache__" / "left-over.cpython.pyc"  # Python writes these when the reader runs
stale.parent.mkdir(parents=True, exist_ok=True)
stale.write_bytes(b"older install")
again = run(str(INSTALL), "--to", str(to))
check("second install exits 0", again.returncode == 0, again.stderr)
check("nothing of the first install is left", not stale.exists())
check("no temporary folder is left", sorted(p.name for p in to.parent.iterdir()) == ["reader"],
      str(list(to.parent.iterdir())))

# 3. From another checkout whose capture source is old: the installed copy is new, so the
#    reader's capture_tool() rebuilds rather than keep a tool built from another source.
repo = tmp / "repo"
(repo / "tools").mkdir(parents=True)
for name in FILES + ("install_reader.py",):
    shutil.copy(TOOLS / name, repo / "tools" / name)
os.utime(repo / "tools" / "strip_capture.swift", (946684800, 946684800))  # 1 Jan 2000
git(repo, "init", "-q")
git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "add", ".")
git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "reader")
to2 = tmp / "other" / "reader"
fresh = run(str(repo / "tools" / "install_reader.py"), "--to", str(to2), cwd=tmp)
check("an install from another folder exits 0", fresh.returncode == 0, fresh.stderr)
check("the installed capture source is newer than the checkout's",
      (to2 / "strip_capture.swift").stat().st_mtime > 946684800 + 86400 if (to2 / "strip_capture.swift").exists() else False)


def refused(name, args, needle):
    before = {p: p.read_bytes() for p in to.rglob("*") if p.is_file()}
    done = run(*args)
    check(name, done.returncode == 1 and needle in done.stderr, "exit %d %s" % (done.returncode, done.stderr))
    check(name + ": nothing changed", {p: p.read_bytes() for p in to.rglob("*") if p.is_file()} == before
          and sorted(p.name for p in to.parent.iterdir()) == ["reader"])


# 4. Refusals. A reader file that differs from the commit:
with open(repo / "tools" / "strip1.py", "a") as f:
    f.write("# not committed\n")
refused("a changed reader file stops the install", [str(repo / "tools" / "install_reader.py"), "--to", str(to)], "strip1.py")
# ... the same with git told to look away from it:
git(repo, "update-index", "--assume-unchanged", "tools/strip1.py")
refused("a changed file git is told to ignore stops the install", [str(repo / "tools" / "install_reader.py"), "--to", str(to)], "strip1.py")
# ... a folder that holds other things (here a checkout) is never replaced:
keep = tmp / "checkout"
keep.mkdir()
(keep / "VERSION").write_text("x\n")
(keep / "precious.txt").write_text("keep me\n")
done = run(str(INSTALL), "--to", str(keep))
check("a folder with other things stops the install", done.returncode == 1 and "not an earlier reader install" in done.stderr,
      "exit %d %s" % (done.returncode, done.stderr))
check("that folder is untouched", sorted(p.name for p in keep.iterdir()) == ["VERSION", "precious.txt"])
# ... nor a folder with only some of an install, or with a folder where a reader file goes:
for label, make in (("only VERSION", lambda d: (d / "VERSION").write_text("x\n")),
                    ("a folder named strip1.py", lambda d: ((d / "VERSION").write_text("x\n"),
                                                           (d / "strip1.py").mkdir(), (d / "strip1.py" / "precious.txt").write_text("keep\n"))),
                    ("a whole install with a folder named strip1.py", lambda d: (
                        [shutil.copy(to / n, d / n) for n in FILES + ("VERSION",) if n != "strip1.py"],
                        (d / "strip1.py").mkdir(), (d / "strip1.py" / "precious.txt").write_text("keep\n")))):
    part = tmp / ("part-" + label.replace(" ", "-"))
    part.mkdir()
    make(part)
    before = sorted(str(q.relative_to(part)) for q in part.rglob("*"))
    done = run(str(INSTALL), "--to", str(part))
    check("%s stops the install" % label, done.returncode == 1 and "not an earlier reader install" in done.stderr,
          "exit %d %s" % (done.returncode, done.stderr))
    check("%s: untouched" % label, sorted(str(q.relative_to(part)) for q in part.rglob("*")) == before)
# ... a process list that cannot be read is not "no reader runs":
fake = tmp / "fakebin"
fake.mkdir()
(fake / "ps").write_text("#!/bin/sh\nexit 1\n")
(fake / "ps").chmod(0o755)
before = {q: q.read_bytes() for q in to.rglob("*") if q.is_file()}
done = subprocess.run([sys.executable, str(INSTALL), "--to", str(to)], capture_output=True, text=True,
                      env=dict(os.environ, PATH="%s:%s" % (fake, os.environ.get("PATH", ""))))
check("a failed process list stops the install", done.returncode == 1 and "cannot list the processes" in done.stderr,
      "exit %d %s" % (done.returncode, done.stderr))
check("a failed process list: nothing changed", {q: q.read_bytes() for q in to.rglob("*") if q.is_file()} == before)
# ... and a reader that runs from the folder:
runner = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", str(to / "hellolink_strip.py")])
try:
    refused("a running reader stops the install", [str(INSTALL), "--to", str(to)], "runs from")
finally:
    runner.kill()
    runner.wait()
runner = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", str(to / "assistant.py")])
try:
    refused("a running assistant program stops the install too", [str(INSTALL), "--to", str(to)], "runs from")
finally:
    runner.kill()
    runner.wait()

shutil.rmtree(tmp)
print("== %d checks, %d failed" % (checks, failed))
sys.exit(1 if failed else 0)
