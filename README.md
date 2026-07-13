# skills

Personal skills library, consumed by two different CLIs that expect two
different layouts:

## Claude Code — flat `<name>.md`

Claude Code loads skills as flat Markdown files (frontmatter + prompt body),
one per skill, e.g. `ralph-review.md`. These are wired up via symlinks from
`~/.claude/commands/<name>.md` -> `~/src/skills/<name>.md`, which is what
makes `/ralph-review` available as a slash command in Claude Code sessions.

## Codex — `<name>/SKILL.md` + `agents/openai.yaml`

Codex expects a subdirectory per skill containing:
- `SKILL.md` — same frontmatter + prompt body idea, but with Codex-oriented
  wording (e.g. it explicitly notes git-mutating side effects and gates
  invocation on explicit user request/authorization).
- `agents/openai.yaml` — Codex-specific interface/policy config
  (`interface.display_name`, `interface.short_description`,
  `interface.default_prompt`, `policy.allow_implicit_invocation`, etc.).

For `ralph-review`, both formats currently exist side by side
(`ralph-review.md` for Claude Code, `ralph-review/` for Codex) and are
maintained independently — edits to one do NOT propagate to the other.
Keep both in sync by hand when changing the skill's behavior.

As of 2026-07-13, `ralph-review/` is untracked in this repo's git history
(added on disk but never committed) — commit it if it should ship for Codex.
