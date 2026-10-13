#!/usr/bin/env bash
# Launch an independent, review-only Codex run in the background and wire it to an
# agent-bus thread.
#
# Usage: start-review.sh <prompt-file> <thread> [reviewer-name]
#
# Environment:
#   AGENT_BUS_DIR  bus root (default: $HOME/agent-bus). Threads live in $AGENT_BUS_DIR/threads.
#   REVIEW_ROOT    repository/worktree the reviewer runs in (default: current directory).
#   CODEX_BIN      codex executable (default: codex).
#   ORCHESTRATOR   name used for the request message and STATUS line (default: orchestrator).
#   RUN_DIR        where the composed prompt, log and final message go
#                  (default: ${TMPDIR:-/tmp}/agent-bus-runs/<thread>). Kept out of the
#                  thread folder so watchers only wake on real messages.
#
# Posts a `kind: request` message to the thread, sets the orchestrator's STATUS.md line,
# and prints the reviewer PID, the log path and the final-message path.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <prompt-file> <thread> [reviewer-name]" >&2
  exit 2
}

[ "$#" -ge 2 ] || usage
prompt_file=$1
thread=$2
reviewer=${3:-codex-$thread}

[ -f "$prompt_file" ] || { echo "prompt file not found: $prompt_file" >&2; exit 1; }
case "$thread" in
  */* | .* | "") echo "thread must be a plain folder name: $thread" >&2; exit 1 ;;
esac

# Write a message atomically: temp file in the same folder, then mv.
post_message() {
  local dir=$1 name=$2 body=$3 tmp
  tmp=$(mktemp "$dir/.tmp.XXXXXX")
  printf '%s\n' "$body" > "$tmp"
  mv "$tmp" "$dir/$name"
}

# Replace (or add) this participant's own line in STATUS.md, atomically.
set_status() {
  local file=$1 name=$2 text=$3 tmp
  tmp=$(mktemp "$(dirname "$file")/.tmp.XXXXXX")
  awk -v n="$name: " 'index($0, n) != 1' "$file" > "$tmp"
  printf '%s: %s\n' "$name" "$text" >> "$tmp"
  mv "$tmp" "$file"
}

request_body() {
  printf 'from: %s\nto: %s\nre: Review request (%s)\nkind: request\n\n' \
    "$orchestrator" "$reviewer" "$thread"
  printf 'Review launched in %s. Prompt: %s\nFinal answer will be written to %s.\n' \
    "$review_root" "$composed" "$final"
}

bus_dir=${AGENT_BUS_DIR:-$HOME/agent-bus}
review_root=${REVIEW_ROOT:-$PWD}
codex_bin=${CODEX_BIN:-codex}
orchestrator=${ORCHESTRATOR:-orchestrator}
thread_dir=$bus_dir/threads/$thread
stamp=$(date -u +%Y%m%dT%H%M%SZ)
tmp_base=${TMPDIR:-/tmp}
run_dir=${RUN_DIR:-${tmp_base%/}/agent-bus-runs/$thread}

command -v "$codex_bin" >/dev/null 2>&1 || { echo "codex not found: $codex_bin" >&2; exit 1; }
mkdir -p "$thread_dir" "$run_dir"
[ -f "$thread_dir/STATUS.md" ] || : > "$thread_dir/STATUS.md"

composed=$run_dir/$stamp-$reviewer.prompt.md
log=$run_dir/$stamp-$reviewer.log
final=$run_dir/$stamp-$reviewer.final.md

# Compose: the caller's prompt, then the coordination footer. printf + cat, never sed:
# prompt text may contain any character.
{
  cat "$prompt_file"
  printf '\n\nCoordination: read %s/README.md and follow it. Name: %s. Thread: %s/.\n' \
    "$bus_dir" "$reviewer" "$thread_dir"
  printf '%s\n' "Post exactly one message (kind: findings): findings P0-P3 (file:line," \
    "evidence or repro, proposed fix), verification you ran, merge readiness, and the exact" \
    "head you reviewed. Update your STATUS.md line. End your final answer with the same summary."
} > "$composed"

nohup "$codex_bin" exec -C "$review_root" --skip-git-repo-check \
  -s workspace-write -c sandbox_workspace_write.network_access=true \
  --add-dir "$bus_dir" -o "$final" - < "$composed" > "$log" 2>&1 &
pid=$!

post_message "$thread_dir" "$stamp-$orchestrator.md" "$(request_body)"
set_status "$thread_dir/STATUS.md" "$orchestrator" \
  "review requested from $reviewer at $stamp (pid $pid); waiting for findings."

echo "reviewer: $reviewer"
echo "pid:      $pid"
echo "thread:   $thread_dir"
echo "prompt:   $composed"
echo "log:      $log"
echo "final:    $final"
echo "wait:     while kill -0 $pid 2>/dev/null; do sleep 30; done"
