---
name: ralph-review
description: Iteratively check Git changes for bugs, code smells, and security issues -- spawning subagents to fix each issue until no major issues are found or 10 cycles are complete. This workflow commits the existing work, each fix cycle, and a marker commit; use only when the user explicitly requests Ralph review and authorizes those Git mutations.
---

You are performing an iterative deep review of the current git changes. Your goal is to find and fix bugs and code smells, cycling until a cycle finds no major issues or you have completed 10 review cycles.

## Stopping condition

Keep cycling until a cycle finds no major issues, fixing everything found along the way. Minor issues found in that final cycle are listed as remaining issues, not fixed. Stop after 10 cycles regardless.

Note: Ralph review doesn't count toward a deploy gate that checks recorded reviews (see agent-bus-review, "What a deploy gate should check").

**Long reviews go to the user before production.** If a change needed more than 3 review cycles (or rounds, counting every reviewer together), tell the user before it is deployed to production: the change, the cycle count, what kept coming up, and whether a different high-level approach would remove the churn (a simpler design, an existing library, moving the responsibility to another layer). A long loop usually means the approach is wrong rather than that more fixes are needed. Merging and staging can go ahead; the production deploy waits until the user has been told. Put this in the final summary too.

## Modes

- **Default** — before the review cycles, investigate major refactors the change suggests (Step 1) and report them to the user.
- **Fast** — invoked with the argument `fast` (e.g. `/ralph-review fast`). Skips the major-refactor investigation and goes straight to the review cycles. The stopping condition is unchanged.

## Process

### Step 0: Snapshot commit (once, before the first cycle)
Record the review baseline: `BASE=$(git rev-parse HEAD)`. Then, if there are any
uncommitted changes (staged or unstaged), commit them all with a normal
descriptive commit message — **no** `[ralph-review]` prefix, since this is the
user's work, not the review's. If the tree is already clean when invoked, set
`BASE` to `HEAD~1` instead, so the review covers the most recent commit.

This way the user's work is preserved as-is, and every subsequent fix lands as
its own clearly-marked commit.

### Step 1: Major-refactor investigation (default mode only, once, before the first cycle)
Spawn an Agent to read `git diff $BASE` and look for major refactors the change suggests: restructurings significant enough that the user may or may not want to proceed, but should know about — e.g. collapsing a layer of indirection, reframing a state model so whole families of branches disappear, moving a responsibility to the layer that should own it, or splitting up a module the change is outgrowing. Don't surface small cleanups here — anything a fix agent could safely do in one sitting is an ordinary smell for the review cycles to catch. Each suggestion should name the refactor, the files/areas affected, the payoff, and a rough sense of scope and risk.

This step gates the review: run it to completion before launching the first review cycle — don't start the cycle-1 reviewer in parallel with it. Report the suggestions to the user as soon as they're in, with a recommendation for each: implement now (before the bug/smell cycles), document in a report or plan file for later, or skip. Then ask the user how to proceed. Implement chosen refactors with fix agents and commit them as `[ralph-review] refactor: <short summary>` — the review cycles will then cover the restructured code like any other change. If the user asks for a report or plan instead, write it up rather than implementing. Suggestions that aren't implemented don't count toward the stopping condition. Skip this step entirely in fast mode.

For each cycle (up to 10):

### Step 2: Analyze changes in a subagent
Spawn an Agent to run `git diff $BASE` (which covers the snapshot commit plus any fixes so far), review all changed code for bugs and code smells, and return a structured list of issues found. Each issue should include a description, severity (major/minor), the file path(s) and line numbers involved. This keeps the diff out of the main agent's context.

Run this agent **in the background** so the main conversation stays responsive: the user can ask you questions or give instructions while the review runs. When the agent's completion notification arrives, continue to Step 3. Don't act on interim findings — the issue list is only final once the agent completes.

### Step 3: Fix issues with subagents
If issues were found, spawn one Agent per issue (or per closely-related group of issues) to fix them. Each agent should receive a clear description of the specific bug or smell and the file path(s) and line numbers involved.

Launch independent fix agents in parallel when the fixes don't overlap in the same code regions. Launch them sequentially if they touch the same lines.

**Pick the model per agent.** Fixing a described issue is mostly mechanical, so fix agents don't need the tier that found it. Decide at runtime from what this harness actually offers rather than hardcoding a model name: enumerate the model tiers available to subagents here (in Claude Code, the Agent tool's `model` parameter; elsewhere, whatever the harness exposes) and give fix agents the cheapest, fastest tier that can still edit code and run the verification command. Keep Step 1 and Step 2 on the session's default model — finding issues is the harder job. Escalate an individual fix agent to the stronger tier when its issue is subtle, spans several files, or came back unfixed from a cheaper agent, and say in the cycle summary which issues needed the escalation. If the harness exposes no model choice, every agent just runs on the session model.

If a fix would break or change the functionality the code was originally meant to deliver, the fix agent must not apply it — it should report the conflict back to the main agent instead. The main agent then describes the issue and the proposed "fix" to the user and asks whether to proceed; leave it out of the cycle's commit unless the user approves.

### Step 4: Commit the cycle's fixes
If any fixes were applied this cycle, commit them with a message starting with
`[ralph-review]`, e.g. `[ralph-review] cycle N: fix <short summary of issues>`.
Thanks to the Step 0 snapshot, these commits contain only the review's fixes,
cleanly separated from the user's work.

### Step 5: Loop
If this cycle found any major issues, start the next cycle (back to Step 2).

### Step 6: Marker commit (after the loop ends)
Every run must leave a `[ralph-review]` commit so
`git log --grep='\[ralph-review\]'` shows when ralph-review last ran. If no fix
commits were made during the entire run, make an empty marker commit:
`git commit --allow-empty -m "[ralph-review] clean review, no issues (M cycles)"`.

## Output format

At the start of each cycle, print:

```
## Review cycle N/10
```

At the end of each cycle, print the issues found and fixes applied, broken down by severity (e.g. "2 major, 3 minor"). For each issue, give a detailed explanation without jargon or shorthand — not a one-line summary: what the defect is, the concrete failure scenario (inputs/state → wrong behavior), and what the fix changed. Write it so a reader who hasn't seen the diff or the subagent reports understands each bug and its consequences, in plain language — no jargon, abbreviations, or shorthand labels invented during the run. When the entire review is done print a final summary:

```
## Ralph review complete
- Cycles: N
- Issues found: X (A major, B minor)
- Issues fixed: Y (C major, D minor)
- Remaining issues: Z (if any, list them with severity)
- Suggested major refactors: S (default mode only; note each one's disposition — implemented, documented in a report/plan, or declined)
- Fixes you may not have wanted: F (highlight any fix that reverted or undid what the reviewed changes were doing — anything that worked against the apparent intent of the work under review — with what changed and whether the user approved it or it was left out)
```

## Important rules
- Read AGENTS.md before starting to understand project constraints
- If an issue is ambiguous or the right fix is unclear, note it in the summary rather than guessing
