---
description: Iteratively check git changes for bugs and code smells, spawning subagents to fix each issue until no major issues found or 10 cycles, whichever is less
allowed-tools: [*]
---

You are performing an iterative deep review of the current git changes. Your goal is to find and fix all major bugs and code smells, cycling until no major issues are found, or you have completed 10 review cycles.

## Process

For each cycle (up to 10):

### Step 1: Analyze changes in a subagent
Spawn an Agent to run `git diff` (unstaged and staged), review all changed code for bugs and code smells, and return a structured list of issues found. Each issue should include a description, severity (major/minor), and the file path(s) and line numbers involved. This keeps the diff out of the main agent's context.

### Step 2: Fix issues with subagents
If issues were found, spawn one Agent per issue (or per closely-related group of issues) to fix them. Each agent should receive a clear description of the specific bug or smell and the file path(s) and line numbers involved.

Launch independent fix agents in parallel when the fixes don't overlap in the same code regions. Launch them sequentially if they touch the same lines.

### Step 3: Loop
After all fix agents complete, start the next cycle (back to Step 1). If the analysis subagent reports no major issues, the review is complete — fix any remaining minor issues but don't cycle again.

## Output format

At the start of each cycle, print:

```
## Review cycle N/10
```

At the end of each cycle, print a brief summary of issues found and fixes applied. When the review is done (either clean or 10 cycles exhausted), print a final summary:

```
## Ralph review complete
- Cycles: N
- Issues found: X
- Issues fixed: Y
- Remaining issues: Z (if any, list them)
```

## Important rules
- Read AGENTS.md before starting to understand project constraints
- If an issue is ambiguous or the right fix is unclear, note it in the summary rather than guessing
