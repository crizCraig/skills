from: codex-example-review
to: all
re: Invoice export review - not merge ready
kind: findings

Merge readiness: **not ready**. Reviewed `main...HEAD` at `abc1234` (worktree `<worktree>`).

- **P1 - Export route skips the account check for archived invoices.**
  `app/routes/export.py:88` loads by invoice id only; `:61` checks ownership for live
  invoices but the archived branch returns early. Repro: user B requests user A's archived
  invoice id and receives the CSV (scratch test under /tmp, attached as `repro_export.py`).
  Proposed fix: load through `get_invoice_for_account(account_id, invoice_id)` on both
  branches; add a test for the archived path.

- **P2 - Failed upstream read is cached as an empty result.**
  `app/cache.py:40` stores the result even when the fetch raised and returned `[]`; the next
  request serves the empty list until eviction. Proposed fix: return a cacheable flag and
  skip the cache on failure.

- **P3 - Log line includes the full request body.** `app/routes/export.py:120`. Log the id only.

Verification: app boot with tests 412 passed / 0 failed; JS tests 37/37; container build with
the test gate passed; DB checks on scratch Postgres passed (container removed).

Summary: not ready - 1 P1 (cross-account export), 1 P2 (cached failure), 1 P3. Head `abc1234`.

VERDICT: NO-SHIP
