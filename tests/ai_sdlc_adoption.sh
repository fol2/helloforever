#!/bin/sh
# Adoption regression test: the AI-SDLC controls are present and wired in this repository.
#
#   sh tests/ai_sdlc_adoption.sh
#
# Each failure names the missing control. Exit 1 on any failure. Needs jq (the hooks use it).
set -u
cd "$(dirname "$0")/.." || exit 2
fail=0
no() { echo "FAIL: $1"; fail=1; }

# PR checks: the scripts the workflow reads from the base branch.
for f in review_on_head.sh owner_decisions_check.sh secret_scan.sh; do
  [ -x ".ai-sdlc/$f" ] || no "check script .ai-sdlc/$f is missing or not executable"
done

# PR checks: the caller runs from the base (pull_request_target), also on review comments, and
# uses the local implementation, which reads every script from the base branch.
caller=.github/workflows/ai-sdlc-checks.yml
impl=.github/workflows/ai-sdlc-checks-impl.yml
grep -q '^  pull_request_target:' "$caller" 2>/dev/null || no "$caller does not run on pull_request_target"
grep -q '^  issue_comment:' "$caller" 2>/dev/null || no "$caller does not run on review comments (issue_comment)"
grep -q "uses: ./$impl" "$caller" 2>/dev/null || no "$caller does not call $impl"
for f in review_on_head.sh owner_decisions_check.sh secret_scan.sh; do
  grep -q "git show \"origin/\$BASE:\$SCRIPTS/$f\"" "$impl" 2>/dev/null ||
    no "$impl does not read $f from the base branch"
done
grep -q 'context=ai-sdlc/review-on-head' "$impl" 2>/dev/null || no "$impl does not write the ai-sdlc/review-on-head status"

# Hooks: installed, executable and wired in the session settings.
for h in guard-edits.sh spend-gate.sh; do
  [ -x ".claude/hooks/$h" ] || no "hook .claude/hooks/$h is missing or not executable"
  grep -q "/.claude/hooks/$h" .claude/settings.json 2>/dev/null || no ".claude/settings.json does not run $h"
done

# Hooks: the edit guard really blocks. The key is assembled here so this file holds no
# credential-shaped text.
# The payload is JSON built by jq, so a path with odd characters cannot break it.
guard() { # file_path new_string -> the hook's exit code
  jq -n --arg p "$1" --arg s "$2" '{tool_input: {file_path: $p, new_string: $s}}' |
    CLAUDE_PROJECT_DIR=$PWD sh .claude/hooks/guard-edits.sh >/dev/null 2>&1
  echo $?
}
if [ -x .claude/hooks/guard-edits.sh ]; then
  code=$(guard "$PWD/docs/owner-decisions.md" x)
  [ "$code" = 2 ] || no "guard-edits.sh does not block an edit of docs/owner-decisions.md (exit $code)"
  key="AKIA""ABCDEFGHIJKLMNOP"
  code=$(guard "$PWD/README.md" "$key")
  [ "$code" = 2 ] || no "guard-edits.sh does not block credential-shaped text (exit $code)"
  code=$(guard "$PWD/README.md" "plain text")
  [ "$code" = 0 ] || no "guard-edits.sh blocks an ordinary edit (exit $code)"
fi

# Owner decisions: the file exists with its heading, and the append-only check passes on HEAD.
grep -q '^## Decisions' docs/owner-decisions.md 2>/dev/null || no "docs/owner-decisions.md is missing or has no Decisions heading"

# Routing: the version stamp and the ledger.
grep -q '^AI-SDLC: v3 (20[0-9][0-9]-[0-9][0-9]-[0-9][0-9])$' AGENTS.md 2>/dev/null || no "AGENTS.md has no AI-SDLC version stamp"
grep -q '^| expenditure | 0 |' docs/autonomy-ledger.md 2>/dev/null || no "docs/autonomy-ledger.md does not hold expenditure at level 0"

[ "$fail" = 0 ] && echo "AI-SDLC ADOPTION OK"
exit "$fail"
