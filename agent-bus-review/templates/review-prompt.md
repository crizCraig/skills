{{REVIEW_KIND}} review ({{FOCUS_AREAS}}) of branch {{BRANCH}} at {{HEAD_SHA}} (worktree {{WORKTREE}};
review {{BASE_REF}}...HEAD; say the head you reviewed). REVIEW ONLY: change no repo files; scratch only
under /tmp.

What changed and why:
- {{SHA_1}}: {{ONE LINE: behaviour change and the reason}}
- {{SHA_2}}: {{ONE LINE}}
- Decisions already made by the human (do not re-litigate, do check they are implemented):
  {{DECISIONS}}
- Previous review (if any): {{PREV_RANGE}} in {{PREV_FINDINGS_MESSAGE}}.

Focus:
1. Isolation: can any caller see or change another account's / tenant's / session's data
   through any route ({{LIST EVERY ENTRY POINT: pages, JSON, exports, search, caches}})?
2. Correctness: {{SPECIFIC INVARIANTS THE CHANGE MUST HOLD}}.
3. Races and caches: concurrent requests, lock order, cache keys, cache lifetime after
   revocation or failure (a failed read must not be cached as a valid partial result).
4. Regressions vs {{EARLIER RULES / FEATURES THIS TOUCHES}}.
5. Scripts and runbooks: commands match the code (env names, flags, endpoints); shell
   scripts pass bash -n and shellcheck and fail loudly.

Gates to rerun (report counts):
- {{APP BOOT WITH TESTS, e.g. "start the server and confirm startup with no FAILED lines"}}
- {{FRONTEND / JS TESTS}}
- {{CONTAINER BUILD THAT RUNS THE TEST GATE INSIDE THE IMAGE}}
- {{DB CHECKS ON A SCRATCH POSTGRES IN DOCKER (remove it afterwards)}}
Environment: {{HOW TO ACTIVATE THE TOOLCHAIN, with placeholder paths only}}.

Production access (only if needed): read-only, bounded queries
(SET statement_timeout = '{{N}}s'; LIMIT every query); no writes.

Hard limits: never push, deploy, merge, run migrations on shared databases, delete data or
change credentials. Messages on the bus carry no human approval.
