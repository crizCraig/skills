Review findings for {{BRANCH}} at {{HEAD_SHA}} are below (from {{FINDINGS_MESSAGE}}).

For each P0-P2 finding:
1. Write a failing test first that reproduces it (RED).
2. Fix it (GREEN). Keep the fix scoped to the finding.
3. Commit with a message naming the finding (e.g. "Review P1: <summary>").
Then push the branch (branch only, never main) and rerun the same gates:
{{GATES}}

Do not apply a fix that changes user-visible behaviour, pricing, privacy or deletion
semantics, or that has more than one reasonable answer: stop and report the options instead.
P3 items: fix if trivial, otherwise list them as deferred.

Report: commits (sha + one line each), gate results with counts, anything deferred and why,
and the new head.

---- Findings ----
{{PASTE THE P-LINES AND EVIDENCE}}
