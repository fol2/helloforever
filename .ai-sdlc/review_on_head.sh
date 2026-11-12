#!/bin/sh
# Review-on-head check: the PR carries an independent APPROVE for exactly this head.
#
#   review_on_head.sh <pr-number> <head-sha> [--repo owner/name]
#
# Reads the PR's comments with gh, oldest first. A comment is a review only when its first
# non-blank line is exactly the verdict (`VERDICT: APPROVE`, `VERDICT: REQUEST CHANGES`, or the
# `**Verdict:**` form) and its second non-blank line is exactly `Reviewed head: <sha>` (12 to 40
# hex characters, backticks allowed). Nothing else in the comment is parsed: no Markdown, no
# fences, no quotes. The check holds when unsure: a comment that carries the two lines on top and
# then any further line starting with `VERDICT:`, `**Verdict:**` or `Reviewed head:` at column 0
# is ambiguous and counts as a REQUEST CHANGES for the head it named, and for this head when any
# of those lines names it. The same holds for any comment that carries such a line outside the two
# lines on top (a verdict with no head under it, a bare line pasted from another review): it holds
# this head unless every head it names is another head. Quote an earlier review with `> ` on every
# line, or not at all. Of the reviews whose head is a prefix of this head, the latest decides.
#
#   exit 0  the latest review of this head is an APPROVE
#   exit 1  no review names this head, or the latest one is a REQUEST CHANGES or ambiguous
#   exit 2  the inputs are wrong or gh failed
#
# Set REVIEW_ON_HEAD_COMMENTS to a file of comment bodies, each ended by a record separator
# (byte 036), to run the check without gh, for tests.
set -u
pr=${1:-}; sha=${2:-}; shift 2 2>/dev/null || { echo "usage: review_on_head.sh <pr> <sha> [--repo owner/name]" >&2; exit 2; }
repo=""
[ "${1:-}" = "--repo" ] && repo=${2:-}
case "$sha" in
  *[!0-9a-f]*|"") echo "REVIEW-ON-HEAD RECORD ERROR: head sha must be hex: '$sha'" >&2; exit 2 ;;
esac
[ ${#sha} -ge 12 ] || { echo "REVIEW-ON-HEAD RECORD ERROR: head sha must have 12 or more characters" >&2; exit 2; }

if [ -n "${REVIEW_ON_HEAD_COMMENTS:-}" ]; then
  bodies=$(cat "$REVIEW_ON_HEAD_COMMENTS" && printf x) || exit 2
else
  command -v gh >/dev/null || { echo "REVIEW-ON-HEAD RECORD ERROR: gh not installed" >&2; exit 2; }
  set -- gh pr view "$pr" --json comments --jq '.comments[] | .body + "\u001e"'
  [ -n "$repo" ] && set -- "$@" --repo "$repo"
  bodies=$("$@" && printf x) || { echo "REVIEW-ON-HEAD RECORD ERROR: gh pr view failed for #$pr" >&2; exit 2; }
fi
bodies=${bodies%x}

# One record per comment. A review is the verdict on the first non-blank line and the head on the
# second. Any other line at column 0 that starts with `VERDICT:`, `**Verdict:**` or `Reviewed head:`
# is a stray line, a verdict on top with no head under it included. A comment with a stray line holds
# this head when it names this head, or names no head at all; one whose named heads are all other
# heads is left alone. The latest well-formed review of this head decides otherwise.
latest=$(printf '%s' "$bodies" | HEAD_SHA="$sha" awk 'BEGIN { RS = "\036"; FS = "\n" }
  function clean_head(l) { sub(/^Reviewed head:[[:space:]]*`?/, "", l); sub(/`?[[:space:]]*$/, "", l); return l }
  {
    verdict = ""; head = ""; seen = 0; stray = 0; mentions = 0; other = 0
    for (i = 1; i <= NF; i++) {
      line = $i; sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*$/ && seen < 2) continue
      is_verdict = (line ~ /^(VERDICT:|\*\*Verdict:\*\*)[[:space:]]*(APPROVE|REQUEST CHANGES)[[:space:]]*$/)
      is_head = (line ~ /^Reviewed head:[[:space:]]*`?[0-9a-f]+`?[[:space:]]*$/)
      if (seen == 0) {
        seen = (is_verdict) ? 1 : 2
        if (is_verdict) { verdict = (line ~ /APPROVE/) ? "APPROVE" : "REQUEST CHANGES"; continue }
      } else if (seen == 1) {
        seen = 2
        if (is_head) { h = clean_head(line); if (length(h) >= 12 && length(h) <= 40) { head = h; continue } }
        stray = 1
      }
      if (line ~ /^(VERDICT:|\*\*Verdict:\*\*|Reviewed head:)/) {
        stray = 1
        if (is_head) {
          h = clean_head(line)
          if (length(h) >= 12 && length(h) <= 40) { if (index(ENVIRON["HEAD_SHA"], h) == 1) mentions = 1; else other = 1 }
        }
      }
    }
    if (seen == 1) stray = 1   # a verdict with nothing under it
    if (head != "") {
      if (index(ENVIRON["HEAD_SHA"], head) == 1) { last = stray ? "AMBIGUOUS" : verdict; last_head = head }
      else if (mentions) { last = "AMBIGUOUS"; last_head = ENVIRON["HEAD_SHA"] }
    } else if (stray && (mentions || !other)) {
      last = "AMBIGUOUS"; last_head = ENVIRON["HEAD_SHA"]
    }
  }
  END { if (last != "") print last "\t" last_head }')

case "$latest" in
  "APPROVE	"*) echo "REVIEW-ON-HEAD OK: the latest review of head ${latest#*	} is an APPROVE"; exit 0 ;;
  "REQUEST CHANGES	"*) echo "REVIEW-ON-HEAD FAIL: the latest review of head ${latest#*	} is a REQUEST CHANGES. Fix, push and get a re-review of the new head."; exit 1 ;;
  "AMBIGUOUS	"*) echo "REVIEW-ON-HEAD FAIL: the latest review of head ${latest#*	} carries a VERDICT or Reviewed head line outside the two lines on top. Post one review with the two lines on top; quote earlier reviews with '> '."; exit 1 ;;
esac
echo "REVIEW-ON-HEAD FAIL: no review names head ${sha}. Get a review of the current head before merging."
exit 1
