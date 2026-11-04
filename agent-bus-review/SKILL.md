---
name: agent-bus-review
description: Orchestrate implement -> independent review -> fix -> quick-final re-check cycles on a feature branch, with an outside reviewer agent (Codex CLI) that reports P0-P3 findings through a shared file-based "agent bus". Use when the user asks for an independent/Codex review of a branch, a merge or release review, a review-fix loop before merge, or to set up the agent bus. Launches background processes and pushes feature branches; merges only where project policy allows and never deploys to production without a human or a machine-checked review gate.
---

You are the **orchestrator**. You delegate implementation to subagents, get every change
reviewed by an independent reviewer agent that cannot modify the code, feed its findings
back to the implementer, and repeat until the reviewer reports nothing at P0/P1. Humans
approve production deploys (or a deploy gate that checks the review records does).

Scripts referenced below live in this skill's `scripts/` folder; templates in `templates/`;
a ready-to-copy bus layout in `bus-template/`.

## When to use

The generic process (a project's own review doc, if it has one, takes precedence):

- **Every change before merge:** a fresh in-harness reviewer (a new agent with none of the
  implementer's context), then the outside reviewer (Codex), each until no P0/P1. Open
  P2s don't block but are listed (in the review record, if the project keeps one, and the
  report) and fixed soon after.
- **Merge review** after a rebase or merge onto a main that moved, or of a branch combining
  separately reviewed branches: the combined diff, conflict resolutions and interactions.
  Independent branches (different files, no shared behaviour) need only the test gates.
- **Whole-release review** before every production deploy or package release: the combined
  diff from what is deployed (or the last published tag) to the commit being shipped,
  focused on interactions. Branches reviewed one at a time still need it: each review saw
  only its own diff.
- Text-only changes that can't affect production: one fresh reviewer for accuracy is enough.

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

Wait on the PID the script prints (`while kill -0 $PID 2>/dev/null; do sleep 30; done`),
your harness's background-task notification, or the thread watcher. Do the next
independent task meanwhile. Never kill or restart other reviewer processes: other sessions'
reviews may be running in parallel.

**Recorded reviews (optional).** A project can wrap the reviewer in a runner that pins the
exact range in the prompt header, binds prompt, range and output by hash in a manifest, and
on SHIP writes a record a deploy gate checks (e.g. `reviews/<repo>/<base>..<head>.json` on
the bus). polychat's `review_runner` is one implementation. When a project has one, use it
for every review that must count; a review run by hand can't be recorded afterwards.

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
reviewed". Repeat steps 3-5 until the reviewer reports no P0/P1 and `VERDICT: SHIP`
(fix the P2s it reports too when the fix is cheap and safe).

**No round limit.** Keep cycling while the findings converge; on long loops post a short
status (phase, what is still open). Stop and ask the human only when the findings stop
converging or a fix needs a decision, and say which P0/P1 (and P2s) remain open.
No limit on rounds is not the same as silence: past 3 rounds the human is told before
production (see Policy).

Each follow-up prompt lists the earlier rounds' findings files, what each fix changed, and
what not to re-raise (accepted residuals, policies the human already settled).

### 6. Release

1. Merge per project policy: where main isn't auto-deployed, agents may merge reviewed,
   gated work; otherwise a human approves the merge.
2. Merge to main in a separate **release worktree**; rerun all gates there.
3. Rebased onto a moved main, or combined branches: run a merge review of the result
   (steps 2-5) before going further.
4. Before production: a whole-release review (deployed commit..release commit) until no
   P0/P1; list its open P2s with the release.
5. Deploy to **staging**; smoke-check the changed paths.
6. A **human** runs the production deploy, or an agent through a deploy mode that verifies
   the recorded reviews itself.

## Finding format

One `findings` message per review cycle:

```
from: <reviewer>
to: all
re: <topic> - <ready | not ready>
kind: findings

Merge readiness: **<ready | not ready>**. Reviewed `<base>...HEAD` at `<sha>`.

1. **P<n> - <one-line title>.** `<file>:<line>` <what is wrong>. Evidence/repro: <steps or
   scratch test under /tmp>. Proposed fix: <concrete change + the test to add>.

Verification: <each gate with counts>.

Summary: <readiness, counts per severity, head reviewed>.

VERDICT: <SHIP | NO-SHIP>
```

Open findings are list items opening with a bold severity; don't list already-fixed items
that way. The last line is exactly `VERDICT: SHIP` (no open P0/P1) or `VERDICT: NO-SHIP`.

Severities:

- **P0** - exploitable now or data loss/corruption; stop everything.
- **P1** - security/isolation/correctness bug a user can hit; blocks merge and release.
- **P2** - real bug in an edge case, cache/race issue, clock skew, missing bound, rollback
  hazard; fix soon, but doesn't block: a SHIP may list open P2s, and they are tracked (the
  review record or release notes list their titles).
- **P3** - smell, missing or weak test, doc drift; optional: fix if cheap, else leave a
  one-line note.

See `bus-template/threads/example-review/` for a sample thread.

## Policy

- Fix clear bugs and security issues without asking (still test-first, still reviewed).
- Ask the human for anything that changes user-visible behaviour, pricing, privacy,
  retention/deletion, or has more than one reasonable answer. Record their decision in the
  next review prompt under "decisions already made".
- Humans approve production deploys (or a gate that checks recorded reviews does); merges
  follow project policy. Agents may deploy to staging when the task says so.
- Reviewers never modify the reviewed code; implementers never self-certify.
- More than 3 review rounds (every reviewer counted together, merge reviews included) means
  the human hears about it before production: the change, the round count, what kept
  recurring, and whether a different high-level approach would remove the churn. Long loops
  usually mean the approach is wrong. Merge and staging can proceed; production waits.

## Lessons learned

- **Build follow-up prompts by prepending (`printf` + `cat`), never `sed`.** A `#` (or `/`,
  `&`) in prompt text silently broke a sed-built prompt.
- **Never wait with `until ! pgrep -f "<name>"`.** The loop's own command line matches the
  pattern, so it never exits. Wait on the PID or on a file.
- **Bound production reads.** `statement_timeout` and `LIMIT` on every read-only query; a
  reviewer exploring production data can load it.
- **Pin the head.** Give the reviewer the exact SHA and require it to state the head it
  reviewed; a review of a moving branch is not a review. Move the worktree to the new head
  before a re-check, or the reviewer reads stale code.
- **Report the gates yourself.** A sandboxed reviewer may not be able to listen on
  localhost, so socket tests fail for it (`listen EPERM`); give it your counts.
- **Ask for the verdict on the last line,** and spell out the scale in the prompt (P0/P1
  block, so NO-SHIP; P2 fix soon, doesn't block). Prompts that put the verdict first or left
  the scale implicit produced verdicts a gate couldn't read.
- **Keep run output out of the thread folder** so watchers only wake on messages.
- **Quick finals stay quick.** Re-check scope is the fixes plus anything they touch; a full
  re-review is a new cycle with a new prompt.
