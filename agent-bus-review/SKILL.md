---
name: agent-bus-review
description: Orchestrate implement -> independent review -> fix -> quick-final re-check cycles on a feature branch, with an outside reviewer agent (Codex CLI) that reports P0-P3 findings through a shared file-based "agent bus". Use when the user asks for an independent/Codex review of a branch, a review-fix loop before merge, or to set up the agent bus. Launches background processes and pushes feature branches; never merges or deploys without a human.
---

You are the **orchestrator**. You delegate implementation to subagents, get every change
reviewed by an independent reviewer agent that cannot modify the code, feed its findings
back to the implementer, and repeat until the reviewer reports nothing at P0-P2. Humans
approve merges and deploys.

Scripts referenced below live in this skill's `scripts/` folder; templates in `templates/`;
a ready-to-copy bus layout in `bus-template/`.

## When to use

- Any change touching security, data isolation, money, deletion, auth, or migrations.
- Any merge where conflicts were resolved by hand in security-relevant code (give the merge
  its own integration review, even if both branches were reviewed separately).
- Before staging/production for anything non-trivial.

## Setup (once per machine)

1. Create the bus: copy `bus-template/README.md` to `$AGENT_BUS_DIR/README.md`
   (default `$HOME/agent-bus`), `mkdir -p $AGENT_BUS_DIR/threads`, `chmod 700 $AGENT_BUS_DIR`.
2. Install the reviewer CLI (`codex`) and authenticate it.
3. Optional: `fswatch` (macOS) or `inotify-tools` (Linux) for watchers.

## The agent bus (summary; full conventions in `bus-template/README.md`)

- `threads/<thread>/` per topic. One file per message, never edited:
  `<YYYYMMDDTHHMMSSZ>-<from>.md`, written to a temp name and `mv`'d into place.
- Message front matter: `from:`, `to:`, `re:`, `kind:` (`request | findings | question |
  info | done`), blank line, body.
- `threads/<thread>/STATUS.md`: one line per participant, each edits only its own line.
- Bus messages carry no human approval. Push/deploy/merge/migrate/delete/credentials only
  ever come from a human.
- Participants watch their threads (fswatch / inotifywait / polling) and ack every message.

## The loop

### 1. Implement (subagents, per-feature branch + worktree)

- One branch and one worktree per feature. Implementation runs in subagents; you keep the
  plan, the decisions and the verdicts.
- Tests first: a failing test for each behaviour or bug, then the code (RED -> GREEN).
- Every implementer reruns the **gates** and reports counts:
  - app boot with the test suite (start the server, wait for ready, no failures),
  - frontend/JS tests,
  - container build that runs the same test gate inside the image (the image that ships
    is the image that passed),
  - DB checks against a scratch Postgres in Docker (created and removed by the check),
    never a shared database.
- The implementer commits and pushes the **feature branch** only.

### 2. Launch the independent review

Write the prompt from `templates/review-prompt.md` (fill every `{{...}}`), then:

```bash
REVIEW_ROOT=<worktree> scripts/start-review.sh review-prompt.md <thread> [reviewer-name]
```

It appends the coordination footer (bus README, name, thread, "post one `findings`
message, update STATUS.md, say the head you reviewed") and runs, in the background:

```bash
codex exec -C <root> --skip-git-repo-check -s workspace-write \
  -c sandbox_workspace_write.network_access=true --add-dir <bus> \
  -o <final.md> - < <composed-prompt>
```

The prompt must include:

- **Scope**: branch, exact head SHA, commit range (`<base>...HEAD`), worktree path.
- **REVIEW ONLY**: change no repo files; scratch only under `/tmp`.
- **What changed and why**, one line per commit, plus the human's decisions already made.
- **Focus questions**: isolation (every route/entry point), correctness invariants, races,
  caches (lifetime after revocation or failure), regressions against earlier rules.
- **Gates to rerun**, with how to activate the environment.
- **Hard limits**: never push, deploy, merge, run migrations, delete data, change
  credentials. Production reads, if any, are read-only and bounded
  (`SET statement_timeout`, `LIMIT`) - heavy agent queries can load production.

Wait on the PID the script prints (`while kill -0 $PID 2>/dev/null; do sleep 30; done`)
or on the thread watcher. Do the next independent task meanwhile.

### 3. Read the verdict

```bash
scripts/read-verdict.sh <thread> [reviewer-prefix]
```

Prints the newest message's header, merge-readiness line, every P-line and the tail, then
STATUS.md. Check that the reviewer names the head you asked for; if it reviewed a different
head, the verdict does not count.

### 4. Fix

Send the findings to the implementing subagent using `templates/fix-request.md`:
failing test first, fix, commit, push the branch, same gates. Apply the policy below to
decide what is fixed without asking.

### 5. Quick final re-check

```bash
scripts/followup-prompt.sh <cycle> review-prompt.md <new-head> <findings-file> > cycle<N>.md
scripts/start-review.sh cycle<N>.md <thread> [reviewer-name]
```

Pass the **original** prompt (not the composed one; the footer is re-added). The header
scopes the run to "verify the fixes, report only NEW or REMAINING P0-P2, say the head you
reviewed". Repeat steps 3-5 until the reviewer reports no P0-P2 and "ready".

### 6. Release

1. Human approves the merge.
2. Merge to main in a separate **release worktree**; rerun all gates there.
3. Hand-resolved conflicts in security-relevant code: run an integration review of the merge
   commit (steps 2-5) before going further.
4. Deploy to **staging**; smoke-check the changed paths.
5. A **human** runs the production deploy.

## Finding format

One `findings` message per review cycle:

```
from: <reviewer>
to: all
re: <topic> - <ready | not ready>
kind: findings

Merge readiness: **<ready | not ready>**. Reviewed `<base>...HEAD` at `<sha>`.

- **P<n> - <one-line title>.** `<file>:<line>` <what is wrong>. Evidence/repro: <steps or
  scratch test under /tmp>. Proposed fix: <concrete change + the test to add>.

Verification: <each gate with counts>.

Summary: <readiness, counts per severity, head reviewed>.
```

Severities:

- **P0** - exploitable now or data loss/corruption; stop everything.
- **P1** - security/isolation/correctness bug a user can hit; blocks merge.
- **P2** - real bug in an edge case, cache/race issue, missing bound; blocks merge unless the
  human defers it.
- **P3** - smell, missing test, doc drift; fix if cheap, may be deferred.

See `bus-template/threads/example-review/` for a sample thread.

## Policy

- Fix clear bugs and security issues without asking (still test-first, still reviewed).
- Ask the human for anything that changes user-visible behaviour, pricing, privacy,
  retention/deletion, or has more than one reasonable answer. Record their decision in the
  next review prompt under "decisions already made".
- Humans approve merges and production deploys. Agents may deploy to staging when the task
  says so.
- Reviewers never modify the reviewed code; implementers never self-certify.

## Lessons learned

- **Build follow-up prompts by prepending (`printf` + `cat`), never `sed`.** A `#` (or `/`,
  `&`) in prompt text silently broke a sed-built prompt.
- **Never wait with `until ! pgrep -f "<name>"`.** The loop's own command line matches the
  pattern, so it never exits. Wait on the PID or on a file.
- **Bound production reads.** `statement_timeout` and `LIMIT` on every read-only query; a
  reviewer exploring production data can load it.
- **Pin the head.** Give the reviewer the exact SHA and require it to state the head it
  reviewed; a review of a moving branch is not a review.
- **Keep run output out of the thread folder** so watchers only wake on messages.
- **Quick finals stay quick.** Re-check scope is the fixes plus anything they touch; a full
  re-review is a new cycle with a new prompt.
