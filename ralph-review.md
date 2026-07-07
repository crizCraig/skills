---
description: Iteratively check git changes for bugs and code smells, spawning subagents to fix each issue until no major issues found or 10 cycles, whichever is less
allowed-tools: [*]
---

You are performing an iterative deep review of the current git changes. Your goal is to find and fix all major bugs and code smells, cycling until no major issues are found, or you have completed 10 review cycles.

## Process

### Step 0: Snapshot commit (once, before the first cycle)
Record the review baseline: `BASE=$(git rev-parse HEAD)`. Then, if there are any
uncommitted changes (staged or unstaged), commit them all with a normal
descriptive commit message — **no** `[ralph-review]` prefix, since this is the
user's work, not the review's. If the tree is already clean when invoked, set
`BASE` to `HEAD~1` instead, so the review covers the most recent commit.

This way the user's work is preserved as-is, and every subsequent fix lands as
its own clearly-marked commit.

For each cycle (up to 10):

### Step 1: Analyze changes in a subagent
Spawn an Agent to run `git diff $BASE` (which covers the snapshot commit plus any fixes so far), review all changed code for bugs and code smells, and return a structured list of issues found. Each issue should include a description, severity (major/minor), and the file path(s) and line numbers involved. This keeps the diff out of the main agent's context.

### Step 2: Fix issues with subagents
If issues were found, spawn one Agent per issue (or per closely-related group of issues) to fix them. Each agent should receive a clear description of the specific bug or smell and the file path(s) and line numbers involved.

Launch independent fix agents in parallel when the fixes don't overlap in the same code regions. Launch them sequentially if they touch the same lines.

### Step 3: Commit the cycle's fixes
If any fixes were applied this cycle, commit them with a message starting with
`[ralph-review]`, e.g. `[ralph-review] cycle N: fix <short summary of issues>`.
Thanks to the Step 0 snapshot, these commits contain only the review's fixes,
cleanly separated from the user's work.

### Step 4: Loop
Start the next cycle (back to Step 1).

### Step 5: Marker commit (after the loop ends)
Every run must leave a `[ralph-review]` commit so
`git log --grep='\[ralph-review\]'` shows when ralph-review last ran. If no fix
commits were made during the entire run, make an empty marker commit:
`git commit --allow-empty -m "[ralph-review] clean review, no issues (M cycles)"`.

**Stopping condition:** If you are Fable (model id `claude-fable-*`), keep going until a cycle finds no major or minor issues at all — fix everything found along the way. Otherwise, keep going until a cycle finds no major issues; in a cycle where only minor issues are found, don't fix them — list them as remaining issues and stop.

## Output format

At the start of each cycle, print:

```
## Review cycle N/10
```

At the end of each cycle, print the issues found and fixes applied, broken down by severity (e.g. "2 major, 3 minor"). For each issue, give a detailed explanation — not a one-line summary: what the defect is, the concrete failure scenario (inputs/state → wrong behavior), and what the fix changed. Write it so a reader who hasn't seen the diff or the subagent reports understands each bug and its consequences. When the review is done (either clean or 10 cycles exhausted), print a final summary:

```
## Ralph review complete
- Cycles: N
- Issues found: X (A major, B minor)
- Issues fixed: Y (C major, D minor)
- Remaining issues: Z (if any, list them with severity)
```

## Important rules
- Read AGENTS.md before starting to understand project constraints
- If an issue is ambiguous or the right fix is unclear, note it in the summary rather than guessing
