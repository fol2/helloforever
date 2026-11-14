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
(bin_dir / "git").write_text('#!/bin/sh\nif [ "$1" = show ]; then [ -n "${REAL_SCRIPT:-}" ] && cat "$REAL_SCRIPT" || printf \'%s\\n\' "$FAKE_SCRIPT"; fi\nexit 0\n')
broken = tmp / "broken"
broken.mkdir()
(broken / "awk").write_text('#!/bin/sh\necho "awk: cannot run" >&2\nexit 2\n')
(bin_dir / "gh").write_text('#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$GH_LOG"\nexit "${GH_EXIT:-0}"\n')
for f in [*bin_dir.iterdir(), *broken.iterdir()]:
    f.chmod(0o755)


def run(line, code, gh_exit=0, comments=None, awk_breaks=False):
    """Runs the step with a check script that prints `line` and exits with `code`. Returns the
    step's exit code and the state it posted."""
    work = tmp / "work"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    log = tmp / "gh.log"
    log.write_text("")
    path = "%s:%s" % (bin_dir, os.environ["PATH"])
    env = dict(os.environ, PATH="%s:%s" % (broken, path) if awk_breaks else path, GH_TOKEN="x", PR="1",
               HEAD="a" * 40, BASE="main", SCRIPTS=".ai-sdlc", RUN_URL="https://example.test/run",
               GITHUB_REPOSITORY="owner/repo", RUNNER_TEMP=str(work), GH_LOG=str(log), GH_EXIT=str(gh_exit),
               FAKE_SCRIPT="echo '%s'; exit %d" % (line, code))
    if comments is not None:     # the real check script, reading these comments in place of gh
        (work / "comments").write_text("".join(body + "\036" for body in comments))
        env.update(REAL_SCRIPT=str(ROOT / ".ai-sdlc/review_on_head.sh"), REVIEW_ON_HEAD_COMMENTS=str(work / "comments"))
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
    # The real check script (.ai-sdlc/review_on_head.sh) with comments in a file.
    ("the real script: no comment is pending", run("", 0, comments=[]) == (0, "pending")),
    ("the real script: an APPROVE of the head is success",
     run("", 0, comments=["VERDICT: APPROVE\nReviewed head: %s\n" % ("a" * 40)]) == (0, "success")),
    ("the real script: an APPROVE of an older head is pending",
     run("", 0, comments=["VERDICT: APPROVE\nReviewed head: %s\n" % ("b" * 40)]) == (0, "pending")),
    ("the real script: a REQUEST CHANGES of the head is a failure",
     run("", 0, comments=["VERDICT: REQUEST CHANGES\nReviewed head: %s\n" % ("a" * 40)]) == (1, "failure")),
    ("the real script: an awk that fails is an error, not a head waiting for its review (#84, review)",
     run("", 0, comments=[], awk_breaks=True)[1] == "error"),
]
shutil.rmtree(tmp, ignore_errors=True)

failed = 0
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== %d checks, %d failed" % (len(checks), failed))
sys.exit(1 if failed else 0)
