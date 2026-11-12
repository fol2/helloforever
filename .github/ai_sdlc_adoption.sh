#!/bin/sh
# Adoption regression test: the AI-SDLC controls are present and wired in this repository.
#
#   sh .github/ai_sdlc_adoption.sh
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

# Hooks: installed and executable.
for h in guard-edits.sh spend-gate.sh; do
  [ -x ".claude/hooks/$h" ] || no "hook .claude/hooks/$h is missing or not executable"
done

# Hooks: wired. The command is read from the session settings exactly as a session would find
# it (the PreToolUse entry whose matcher names the tool), then run. Invalid JSON, a wrong event
# or a wrong matcher leaves the command empty and fails here.
hook_cmd() { # tool name -> the command of the first PreToolUse entry whose matcher names it
  jq -r --arg t "$1" '.hooks.PreToolUse[] | select(.matcher | split("|") | index($t))
    | .hooks[] | select(.type == "command") | .command' .claude/settings.json 2>/dev/null | head -1
}
run_hook() { # command, JSON payload on stdin -> the hook's exit code
  CLAUDE_PROJECT_DIR=$PWD sh -c "$1" >/dev/null 2>&1
  echo $?
}
edit_payload() { jq -n --arg p "$1" --arg s "$2" '{tool_input: {file_path: $p, new_string: $s}}'; }

edit_cmd=$(hook_cmd Edit)
for t in Write MultiEdit NotebookEdit; do
  [ "$(hook_cmd "$t")" = "$edit_cmd" ] || no ".claude/settings.json does not guard $t with the same command as Edit"
done
case "$edit_cmd" in
  *'/.claude/hooks/guard-edits.sh'*)
    code=$(edit_payload "$PWD/docs/owner-decisions.md" x | run_hook "$edit_cmd")
    [ "$code" = 2 ] || no "the Edit hook does not block an edit of docs/owner-decisions.md (exit $code)"
    # Assembled here so this file holds no credential-shaped text.
    key="AKIA""ABCDEFGHIJKLMNOP"
    code=$(edit_payload "$PWD/README.md" "$key" | run_hook "$edit_cmd")
    [ "$code" = 2 ] || no "the Edit hook does not block credential-shaped text (exit $code)"
    code=$(edit_payload "$PWD/README.md" "plain text" | run_hook "$edit_cmd")
    [ "$code" = 0 ] || no "the Edit hook blocks an ordinary edit (exit $code)"
    ;;
  *) no ".claude/settings.json has no PreToolUse command for Edit that runs guard-edits.sh" ;;
esac

bash_cmd=$(hook_cmd Bash)
case "$bash_cmd" in
  *'/.claude/hooks/spend-gate.sh'*)
    code=$(jq -n '{tool_input: {command: "ls"}}' | run_hook "$bash_cmd")
    [ "$code" = 0 ] || no "the Bash hook does not let an ordinary command through (exit $code)"
    ;;
  *) no ".claude/settings.json has no PreToolUse command for Bash that runs spend-gate.sh" ;;
esac

# Owner decisions: the file exists with its heading, and the append-only check passes on HEAD.
grep -q '^## Decisions' docs/owner-decisions.md 2>/dev/null || no "docs/owner-decisions.md is missing or has no Decisions heading"

# Routing: the version stamp and the ledger.
grep -q '^AI-SDLC: v3 (20[0-9][0-9]-[0-9][0-9]-[0-9][0-9])$' AGENTS.md 2>/dev/null || no "AGENTS.md has no AI-SDLC version stamp"
grep -q '^| expenditure | 0 |' docs/autonomy-ledger.md 2>/dev/null || no "docs/autonomy-ledger.md does not hold expenditure at level 0"

[ "$fail" = 0 ] && echo "AI-SDLC ADOPTION OK"
exit "$fail"
