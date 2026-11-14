#!/usr/bin/env python3
"""The review-on-head step of .github/workflows/ai-sdlc-checks-impl.yml (#84): a head that no
review names yet is `pending`, not a failure, so a push does not turn the pull request red before
its review is posted. A REQUEST CHANGES, an unclear verdict and a script error still fail.
The step's own shell is run, as the workflow holds it, with a fake `git`, `gh` and check script.
Usage: python3 tests/ai_sdlc_review_status_test.py"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
workflow = (ROOT / ".github/workflows/ai-sdlc-checks-impl.yml").read_text()

# The step's `run: |` block: from the line after `run: |` in the review-on-head job to the first
# line that is indented less.
job = workflow[workflow.index("\n  review-on-head:"):]
job = job[:job.index("\n  owner-decisions:")]
lines = job[job.index("        run: |\n") + len("        run: |\n"):].splitlines()
body = []
for line in lines:
    if line.strip() and not line.startswith("          "):
        break
    body.append(line[10:])
script = "\n".join(body) + "\n"

tmp = Path(tempfile.mkdtemp(prefix="ai-sdlc-status-"))
bin_dir = tmp / "bin"
bin_dir.mkdir()
(bin_dir / "git").write_text('#!/bin/sh\n[ "$1" = show ] && printf \'%s\\n\' "$FAKE_SCRIPT"\nexit 0\n')
(bin_dir / "gh").write_text('#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$GH_LOG"\nexit "${GH_EXIT:-0}"\n')
for f in bin_dir.iterdir():
    f.chmod(0o755)


def run(line, code, gh_exit=0):
    """Runs the step with a check script that prints `line` and exits with `code`. Returns the
    step's exit code and the state it posted."""
    work = tmp / "work"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    log = tmp / "gh.log"
    log.write_text("")
    env = dict(os.environ, PATH="%s:%s" % (bin_dir, os.environ["PATH"]), GH_TOKEN="x", PR="1",
               HEAD="a" * 40, BASE="main", SCRIPTS=".ai-sdlc", RUN_URL="https://example.test/run",
               GITHUB_REPOSITORY="owner/repo", RUNNER_TEMP=str(work), GH_LOG=str(log), GH_EXIT=str(gh_exit),
               FAKE_SCRIPT="echo '%s'; exit %d" % (line, code))
    done = subprocess.run(["bash", "-e", "-c", script], cwd=work, env=env, capture_output=True, text=True)
    state = re.search(r"state=(\w+)", log.read_text())
    return done.returncode, state and state.group(1)


NONE = "REVIEW-ON-HEAD FAIL: no review names head %s. Get a review of the current head before merging." % ("a" * 40)
checks = [
    ("a head that no review names yet is pending, and the step passes", run(NONE, 1) == (0, "pending")),
    ("an APPROVE is success", run("REVIEW-ON-HEAD OK: the latest review of head %s is an APPROVE" % ("a" * 40), 0) == (0, "success")),
    ("a REQUEST CHANGES is a failure, and the step fails",
     run("REVIEW-ON-HEAD FAIL: the latest review of head %s is a REQUEST CHANGES. Fix, push and get a re-review." % ("a" * 40), 1) == (1, "failure")),
    ("an unclear verdict is a failure",
     run("REVIEW-ON-HEAD FAIL: the latest review of head %s carries a VERDICT or Reviewed head line outside the two lines on top" % ("a" * 40), 1) == (1, "failure")),
    ("a script error is an error", run("REVIEW-ON-HEAD RECORD ERROR: gh pr view failed for #1", 2) == (2, "error")),
    ("a pending status that cannot be written fails the step", run(NONE, 1, gh_exit=1)[0] == 2),
]
shutil.rmtree(tmp, ignore_errors=True)

failed = 0
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== %d checks, %d failed" % (len(checks), failed))
sys.exit(1 if failed else 0)
