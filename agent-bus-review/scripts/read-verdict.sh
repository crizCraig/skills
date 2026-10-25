#!/usr/bin/env bash
# Print a compact summary of the newest message in an agent-bus thread: its header,
# the merge-readiness line, every P0-P3 finding line and the tail, then STATUS.md.
#
# Usage: read-verdict.sh <thread> [from-prefix] [tail-lines]
#   from-prefix  only consider messages whose file name contains -<prefix> (e.g. codex)
# Messages with `kind: request` (e.g. the ones start-review.sh posts) are skipped.
#   tail-lines   lines of the message tail to print (default 15)
#
# Environment: AGENT_BUS_DIR (default: $HOME/agent-bus).
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: $(basename "$0") <thread> [from-prefix] [tail-lines]" >&2; exit 2; }
thread=$1
from=${2:-}
tail_lines=${3:-15}
thread_dir=${AGENT_BUS_DIR:-$HOME/agent-bus}/threads/$thread

[ -d "$thread_dir" ] || { echo "no such thread: $thread_dir" >&2; exit 1; }

# Message names start with a UTC timestamp, so a lexical sort is chronological.
newest=""
for f in "$thread_dir"/[0-9]*T[0-9]*Z-*.md; do
  [ -f "$f" ] || continue
  if [ -n "$from" ]; then
    case "$(basename "$f")" in *"-$from"*) ;; *) continue ;; esac
  fi
  grep -q '^kind: request' "$f" && continue
  newest=$f
done
[ -n "$newest" ] || { echo "no messages in $thread_dir" >&2; exit 1; }

echo "== $(basename "$newest")"
# Header: everything up to the first blank line.
awk 'NF == 0 { exit } { print }' "$newest"
echo
echo "== readiness"
grep -iE 'merge readiness|ready for|not ready|readiness:|^[[:space:]*#>_]*VERDICT' "$newest" \
  | head -4 || echo "(none)"
echo
echo "== findings"
grep -E '^[[:space:]]*([-*]|[0-9]+\.)?[[:space:]]*(\*\*)?P[0-3]([^0-9]|$)' "$newest" \
  | cut -c1-220 || echo "(no P0-P3 lines)"
echo
echo "== tail"
tail -n "$tail_lines" "$newest"
if [ -s "$thread_dir/STATUS.md" ]; then
  echo
  echo "== STATUS.md"
  cat "$thread_dir/STATUS.md"
fi
