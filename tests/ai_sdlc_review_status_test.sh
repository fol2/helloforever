#!/bin/sh
# The review-on-head step of .github/workflows/ai-sdlc-checks-impl.yml (#84): a head that no
# review names yet is `pending`, not a failure, so a push does not turn the pull request red
# before its review is posted. A REQUEST CHANGES, an unclear verdict and a script error still
# fail. The step's own shell is run, as the workflow holds it, with a fake `git`, `gh` and check
# script. (In Python until #195 step 3c.)
# Usage: sh tests/ai_sdlc_review_status_test.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ai-sdlc-status-XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# The step's `run: |` block in the review-on-head job: the lines after it, to the first line
# that is not blank and is indented less.
awk '
  /^  review-on-head:/ { job = 1; next }
  /^  owner-decisions:/ { job = 0 }
  job && !body && $0 == "        run: |" { body = 1; next }
  body { if ($0 ~ /[^ ]/ && substr($0, 1, 10) != "          ") exit; print substr($0, 11) }
' "$ROOT/.github/workflows/ai-sdlc-checks-impl.yml" > "$tmp/step.sh"

mkdir "$tmp/bin" "$tmp/broken"
cat > "$tmp/bin/git" <<'EOF'
#!/bin/sh
if [ "$1" = show ]; then [ -n "${REAL_SCRIPT:-}" ] && cat "$REAL_SCRIPT" || printf '%s\n' "$FAKE_SCRIPT"; fi
exit 0
EOF
cat > "$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
exit "${GH_EXIT:-0}"
EOF
printf '#!/bin/sh\necho "awk: cannot run" >&2\nexit 2\n' > "$tmp/broken/awk"
chmod 755 "$tmp/bin/git" "$tmp/bin/gh" "$tmp/broken/awk"

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# run LINE CODE [GH_EXIT] [COMMENTS] [AWK_BREAKS]: the step, with a check script that prints
# LINE and exits CODE; with COMMENTS (a file, "-" for none), the real check script reads them
# in place of gh. Prints the step's exit code and the state it posted.
run() {
    rm -rf "$tmp/work" && mkdir "$tmp/work" && : > "$tmp/gh.log"
    path="$tmp/bin:$PATH"
    [ -n "${5:-}" ] && path="$tmp/broken:$path"
    (
        cd "$tmp/work" || exit 99
        export PATH="$path" GH_TOKEN=x PR=1 HEAD=$A BASE=main SCRIPTS=.ai-sdlc \
            RUN_URL=https://example.test/run GITHUB_REPOSITORY=owner/repo RUNNER_TEMP="$tmp/work" \
            GH_LOG="$tmp/gh.log" GH_EXIT="${3:-0}" FAKE_SCRIPT="echo '$1'; exit $2"
        if [ -n "${4:-}" ]; then
            export REAL_SCRIPT="$ROOT/.ai-sdlc/review_on_head.sh" REVIEW_ON_HEAD_COMMENTS="$4"
        fi
        bash -e "$tmp/step.sh" > /dev/null 2>&1
    )
    rc=$?
    echo "$rc $(sed -n 's/.*state=\([a-z]*\).*/\1/p' "$tmp/gh.log" | head -n 1)"
}

# comments FILE BODY...: each body ends with the record separator, as the script reads them
comments() {
    f=$1
    shift
    : > "$f"
    for body in "$@"; do printf '%s\n\036' "$body" >> "$f"; done
}

failed=0 n=0
check() { # NAME GOT WANT
    n=$((n + 1))
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1  -> got '$2', want '$3'"; failed=$((failed + 1)); fi
}

NONE="REVIEW-ON-HEAD FAIL: no review names head $A. Get a review of the current head before merging."
check "a head that no review names yet is pending, and the step passes" "$(run "$NONE" 1)" "0 pending"
check "an APPROVE is success" \
    "$(run "REVIEW-ON-HEAD OK: the latest review of head $A is an APPROVE" 0)" "0 success"
check "a REQUEST CHANGES is a failure, and the step fails" \
    "$(run "REVIEW-ON-HEAD FAIL: the latest review of head $A is a REQUEST CHANGES. Fix, push and get a re-review." 1)" "1 failure"
check "an unclear verdict is a failure" \
    "$(run "REVIEW-ON-HEAD FAIL: the latest review of head $A carries a VERDICT or Reviewed head line outside the two lines on top" 1)" "1 failure"
check "a script error is an error" "$(run "REVIEW-ON-HEAD RECORD ERROR: gh pr view failed for #1" 2)" "2 error"
check "a pending status that cannot be written fails the step" "$(run "$NONE" 1 1 | cut -d' ' -f1)" "2"

# The real check script (.ai-sdlc/review_on_head.sh) with comments in a file.
c="$tmp/comments"
comments "$c"
check "the real script: no comment is pending" "$(run "" 0 0 "$c")" "0 pending"
comments "$c" "VERDICT: APPROVE
Reviewed head: $A"
check "the real script: an APPROVE of the head is success" "$(run "" 0 0 "$c")" "0 success"
comments "$c" "VERDICT: APPROVE
Reviewed head: $B"
check "the real script: an APPROVE of an older head is pending" "$(run "" 0 0 "$c")" "0 pending"
comments "$c" "VERDICT: REQUEST CHANGES
Reviewed head: $A"
check "the real script: a REQUEST CHANGES of the head is a failure" "$(run "" 0 0 "$c")" "1 failure"
comments "$c"
check "the real script: an awk that fails is an error, not a head waiting for its review (#84, review)" \
    "$(run "" 0 0 "$c" broken | cut -d' ' -f2)" "error"

echo "== $n checks, $failed failed"
[ "$failed" -eq 0 ]
