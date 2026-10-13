# skills

Personal skills library, consumed by two different CLIs that expect two
different layouts.

## Index

| Skill | What it does |
| --- | --- |
| `ralph-review` | Iterative in-session review-and-fix loop over the current Git changes. |
| [`agent-bus-review`](agent-bus-review/SKILL.md) | Implement -> independent reviewer (Codex CLI) -> fix -> quick-final re-check loop, coordinated through a file-based agent bus; scripts, prompt templates and a bus template included. |

## Claude Code — flat `<name>.md`

Claude Code loads skills as flat Markdown files (frontmatter + prompt body),
one per skill, e.g. `ralph-review.md`. These are wired up via symlinks from
`~/.claude/commands/<name>.md` -> `~/src/skills/<name>.md`, which is what
makes `/ralph-review` available as a slash command in Claude Code sessions.

## Codex — `<name>/SKILL.md` with optional `agents/openai.yaml`

Codex discovers user-wide skills under `~/.agents/skills`. Each skill is a
subdirectory containing:

- `SKILL.md` — same frontmatter + prompt body idea, but with Codex-oriented
  wording (e.g. it explicitly notes git-mutating side effects and gates
  invocation on explicit user request/authorization).
- `agents/openai.yaml` — Codex-specific interface/policy config
  (`interface.display_name`, `interface.short_description`,
  `interface.default_prompt`, `policy.allow_implicit_invocation`, etc.).

Install the Ralph Review skill for the current user with a symlink so edits in
this repository are picked up automatically:

```bash
mkdir -p ~/.agents/skills
ln -s ~/src/skills/ralph-review ~/.agents/skills/ralph-review
```

Verify the link and skill manifest before starting a new session:

```bash
readlink ~/.agents/skills/ralph-review
test -f ~/.agents/skills/ralph-review/SKILL.md
```

Do not install personal skills under `~/.codex/skills`; it is not a documented
user discovery location. Codex follows skill-directory symlinks and normally
detects changes automatically. Restart Codex if a new or updated skill does not
appear, then use `/skills` to confirm it is available. Codex may omit skills
from the initial prompt's abbreviated catalog when many skills are installed,
but explicit invocation remains available.

See the official OpenAI documentation for the current discovery locations and
symlink behavior: <https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills>.

Ralph Review disables implicit invocation because it mutates Git state. Invoke
it explicitly as `$ralph-review`.

For `ralph-review`, both formats currently exist side by side
(`ralph-review.md` for Claude Code, `ralph-review/` for Codex) and are
maintained independently — edits to one do NOT propagate to the other.
Keep both in sync by hand when changing the skill's behavior.

## agent-bus-review

A single folder (`agent-bus-review/`) used by both CLIs; no separate flat file.
Install by symlinking the folder:

```bash
mkdir -p ~/.claude/skills ~/.agents/skills
ln -s "$PWD/agent-bus-review" ~/.claude/skills/agent-bus-review   # Claude Code
ln -s "$PWD/agent-bus-review" ~/.agents/skills/agent-bus-review   # Codex
```

Then create the bus once from `agent-bus-review/bus-template/` (see the skill's
Setup section). Scripts need bash, `codex`, and optionally `fswatch`/`inotifywait`.
