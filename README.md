# gobind — a Claude Code plugin for how Gobind works

One folder that carries everything: a working-style skill, deterministic hooks, orchestration
agents, slash commands and project templates. Built 2026-09-15 from the memory files,
CLAUDE.md / AGENTS.md files and prompt history across `~/Programming`, plus research into
Anthropic's skill guidance and the instruction-following literature
(`docs/research-and-proposal.md`).

## What it does

**Hooks (deterministic, every session)** in `hooks/hooks.json`, scripts in `scripts/`:

| Hook | Event | Effect |
|---|---|---|
| git-guard | PreToolUse Bash | Read-only git. Mutations denied unless `/gobind:git-allow <branch>`; main/master always locked. |
| secrets-guard | PreToolUse Read/Edit/Write/Bash | No reading, editing or printing `.env*`, keys, credentials, or the whole environment. |
| server-guard | PreToolUse Bash | No `pkill node`, no killing a PID that serves a port, no second dev server on a busy port. |
| question-gate | PreToolUse AskUserQuestion | In autonomous mode questions are denied unless tagged `[stop-condition]`. |
| session-index | SessionStart (startup, resume, clear, compact) | ≤20 lines: mode, branch, head of `docs/status.md`, the five rules. Survives compaction. |
| prompt-reminder | UserPromptSubmit | Timestamp + mode each turn; "going to sleep" / "full autonomous" flips to autonomous, "i'm back" flips to collab. |
| docs-nudge | PostToolUse Edit/Write | After 8 source edits without touching the status doc, one nudge. |
| gate-tracker | PostToolUse Bash | Records lint / typecheck / build / test runs. |
| done-gate | Stop | Autonomous mode only: holds the session open (max twice) until gates ran and the status doc is current. |
| config-guard | PreToolUse Edit/Write/Bash | Editing settings, hooks or plugin scripts asks first. |
| test-guard | PreToolUse Edit/Write/Bash | Skipping, focusing or deleting tests asks first (`/gobind:test-allow` lifts it). |

**Skill** `skills/working-style/`: the rules, mode table, redirect decoder, rationalization
table, reply shapes; references for the full agreement, web conventions and delegation.

**Commands**: `/gobind:mode`, `/gobind:git-allow`, `/gobind:git-lock`, `/gobind:test-allow`,
`/gobind:recap`, `/gobind:handoff`, `/gobind:questions`, `/gobind:rca`, `/gobind:new-project`,
`/gobind:add-rule`.

**Agents** `agents/`: `phase-lead` (Opus), `worker` (Sonnet), `drone` (Haiku).

**Templates** `assets/templates/`: CLAUDE.md, status, log, PRODUCT, DESIGN, CONVENTIONS,
brief, recap, questions, handoff.

Session state lives per project in `.claude/gobind/session-<id>.json` (git-ignore it).

## Install (project-scoped, when you want it)

Nothing is installed globally. Pick one per project:

```bash
# a) try it for one session
claude --plugin-dir ~/Programming/working-style-skill

# b) project-scoped plugin: symlink into the project's skills dir (loads as gobind@skills-dir)
mkdir -p <repo>/.claude/skills
ln -s ~/Programming/working-style-skill <repo>/.claude/skills/gobind
# then /reload-plugins; add .claude/gobind/ to the repo's .gitignore

# c) from a marketplace (any machine): push this folder to GitHub with
#    .claude-plugin/marketplace.json (see docs/marketplace.example.json), then
claude plugin marketplace add theGobindSingh/<repo>
claude plugin install gobind@<marketplace-name> --scope project
```

## Test

```bash
bash tests/run.sh          # 83 hook cases: git, secrets, server, question gate, mode switch, gates
claude plugin validate .   # manifest and layout
```

## Layout

```
.claude-plugin/plugin.json
hooks/hooks.json
scripts/*.sh
skills/working-style/{SKILL.md,references/,evals/}
skills/{mode,git-allow,git-lock,test-allow,recap,handoff,questions,rca,new-project,add-rule}/SKILL.md
agents/{phase-lead,worker,drone}.md
assets/templates/*.template
tests/run.sh
docs/research-and-proposal.md
```
