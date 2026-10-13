#!/usr/bin/env bash
# Build a "CYCLE N quick final" re-check prompt by PREPENDING a header to an existing
# review prompt. Uses printf + cat on purpose: building prompts with sed breaks as soon
# as the prompt contains a delimiter character ('#', '/', '&', ...).
#
# Usage: followup-prompt.sh <cycle> <previous-prompt> <head-sha> [findings-file] > next.md
#   cycle          cycle number, e.g. 2
#   head-sha       the exact commit the reviewer must review
#   findings-file  the previous findings message (path), quoted to the reviewer
set -euo pipefail

[ "$#" -ge 3 ] || {
  echo "usage: $(basename "$0") <cycle> <previous-prompt> <head-sha> [findings-file]" >&2
  exit 2
}
cycle=$1
prev=$2
head_sha=$3
findings=${4:-the newest findings message in the thread}

case "$cycle" in ''|*[!0-9]*) echo "cycle must be a number: $cycle" >&2; exit 1 ;; esac
[ -f "$prev" ] || { echo "previous prompt not found: $prev" >&2; exit 1; }

printf 'CYCLE %s QUICK FINAL re-check at %s. Say the head you reviewed.\n' "$cycle" "$head_sha"
printf 'Scope: verify the fixes for the findings in %s.\n' "$findings"
printf '%s\n' \
  "Report only NEW or REMAINING P0-P2 issues (P3 only if it blocks merge). Do not re-review" \
  "unchanged code beyond what the fixes touch. Rerun the same gates. Same hard limits as" \
  "below: review only, never push, deploy, merge, migrate or change credentials." \
  "" \
  "---- Original prompt (context; its scope is superseded by the lines above) ----" \
  ""
cat "$prev"
