# Research findings and upgrade proposal for `gobind-working-style`

Written 2026-09-15T05:58:00+05:30 from five parallel research passes (official Claude Code docs,
Anthropic skill guidance, community skills such as superpowers / ponytail / caveman / stop-slop /
cc-sessions / claude-handoff / hook packs, and the instruction-following literature).

## 1. What the evidence says (the parts that change the design)

- **Prose is advisory, hooks are deterministic.** Official docs: rules in CLAUDE.md or a skill
  are "a request, not a guarantee"; anything that must happen every time belongs in a
  PreToolUse / Stop hook. Measured: constraints that oppose the model's defaults fail 10-100%
  of the time regardless of wording, while conventional ones pass at 99%+
  (arxiv 2604.07192). Git-read-only, no-`.env`, don't-kill-my-server, and "no questions in
  autonomous mode" all oppose defaults. They should be hooks.
- **Joint compliance collapses past ~5-7 simultaneous hard constraints** (arxiv 2608.12426,
  IFScale 2507.11538). The current SKILL.md carries ~30. Keep 5-7 at the top; push the rest to
  references and hooks.
- **Primacy and trailing reminders.** Earlier rules are followed more; end-of-task rules lose
  up to 50% under load but recover to 90-100% with a reminder just before the action
  (arxiv 2603.23530). So: hard rules first, and a UserPromptSubmit / Stop hook that repeats the
  1-3 rules that matter right now.
- **Compaction drops conversation-only rules.** Root CLAUDE.md and unscoped rules are re-read;
  skills are re-attached truncated to 5k tokens each; anything else may vanish. A SessionStart
  hook with `matcher: compact` re-injects a ≤20-line index.
- **Subagents inherit nothing** except CLAUDE.md. Rules must be restated in briefs or preloaded
  via the agent's `skills:` field.
- **Audit trails beat promises.** Process instructions got 0% behavioural compliance even when
  the model agreed verbally; requiring an auditable artefact raised it to 97%
  (arxiv 2605.01771). Verification evidence should be a required part of the recap.
- **Descriptions must be triggers only.** When a description summarises the workflow, agents
  follow the description and skip the body (superpowers writing-skills). The current
  description summarises. Add `when_to_use`, third person, keep under 1,536 chars combined.
- **Aggressive language over-triggers on current models.** Anthropic: dial back "CRITICAL /
  MUST"; emphasise at most one line.
- **Superpowers devices that survived testing:** rationalization tables (excuse → reality),
  red-flag phrases in the agent's own thinking, decoding of the partner's terse redirects,
  numeric escalation caps, "delete means delete".
- **Mechanics available:** skill frontmatter accepts `hooks:` (active after invocation, session
  long, `once: true`), `when_to_use`, `paths`, `disable-model-invocation`, `user-invocable`,
  `context: fork` + `agent`, `disallowed-tools`, `$ARGUMENTS`. A "skills-directory plugin"
  (`~/.claude/skills/<name>/.claude-plugin/plugin.json`) bundles skill + hooks + agents +
  commands, reads the live folder, no marketplace, `/reload-plugins` after hook edits.

## 2. Proposal, ranked by leverage

### A. Turn it into a skills-directory plugin (foundation for everything below)
Layout: `.claude-plugin/plugin.json`, `skills/gobind-working-style/`, `skills/<commands>/`,
`hooks/hooks.json`, `scripts/*.sh`, `agents/{phase-lead,worker,drone}.md`, `assets/templates/`.
Hooks then run in every session, not only after the skill is invoked. Symlink stays at
`~/.claude/skills/gobind-working-style`; works on WSL via `${CLAUDE_PLUGIN_ROOT}`.

### B. Hooks (deterministic guards for the rules that oppose defaults)
1. **git-guard** (PreToolUse Bash): deny commit/push/pull/merge/rebase/reset/stash/checkout/
   switch/branch -D/add -f/clean with a reason; allow when a session grant exists
   (`/git-allow <branch>` writes `.claude/gobind/git-grant` naming the branch; pushes to
   `main` stay denied even then).
2. **secrets-guard** (PreToolUse Read|Edit|Write|Bash): deny `.env*`, `*.pem`,
   `credentials*.json`, `cat .env`, `printenv` dumps.
3. **server-guard** (PreToolUse Bash): deny `pkill node`, `killall node`, `fuser -k`, `kill`
   of a PID that owns a listening port, and `pnpm dev`/`next dev` when the port is already
   served (reply names the PID and says "reuse it").
4. **mode-aware question gate** (PreToolUse AskUserQuestion): in autonomous mode deny with
   "decide, note the assumption in the recap" unless the question is tagged
   `[stop-condition]`. This is the fix for "why the questions?".
5. **session-index** (SessionStart startup|resume|clear|compact): inject ≤20 lines: mode,
   `date -Iseconds`, branch + short status, head of `docs/status.md`, the 5 hard rules,
   pending handoff pointer.
6. **prompt-reminder** (UserPromptSubmit): inject timestamp + mode; detect autonomy phrases
   ("going to sleep", "full autonomous", "don't ask") and flip the mode file automatically,
   injecting "batch your questions now, then none".
7. **docs-nudge** (PostToolUse Edit|Write, throttled): after N source edits with
   `docs/status.md` untouched, additionalContext "status doc may be stale".
8. **done-gate** (Stop, autonomous mode only): block once if source changed and no lint /
   typecheck / build command ran this session, or `docs/status.md` untouched; cap 2 blocks.
9. **config-guard** (PreToolUse Edit|Write on `.claude/settings*.json`, `hooks/`): ask.
10. **test-guard**: deny deleting test files or adding `.skip`/`xit` without a grant.

### C. Slash commands (user-invocable, `disable-model-invocation: true`)
- `/mode autonomous|collab|status` with optional stop-condition text.
- `/git-allow <branch>` and `/git-lock`.
- `/handoff`: writes goal / state / next steps / constraints / gotchas into `docs/status.md`,
  ISO timestamp, secrets redacted.
- `/recap`: done / remaining / blocked, three lines, evidence per item.
- `/questions`: research read-only first, then one numbered batch, each with a
  recommendation and one-line stakes, structural first.
- `/rca`: bug list → one read-only RCA phase per bug, shared-cause check, then fix phases from
  proven causes only.
- `/new-project <name>`: scaffold CLAUDE.md + docs/{PRODUCT,DESIGN,CONVENTIONS,status,log}.md
  + `.claude/settings.json` from templates; pnpm; no git init.
- `/add-rule "<text>"`: pin the exact form, write to repo CLAUDE.md + skill references +
  memory with ISO timestamp.

### D. Rewrite the SKILL.md body per the research
- 5-7 hard constraints first; everything else moves to references or hooks.
- Description = triggers only, third person; add `when_to_use`; run the description optimizer.
- Add a rationalization table and red-flag phrases tuned to his actual corrections.
- Add a "decode his redirects" table: "why the questions?" / "so not 'we dont know'" /
  "its been 2 hours whats happening" / "no its wrong, i want..." / "how do you know this?".
- Good vs bad reply examples (status answer, recap, question batch, subagent brief).
- Positive phrasing ("do Y instead of X"), no nuance clauses, one emphasised line max.
- Numeric caps: 3 failed fixes → question the architecture; agent silent > 20 min → check;
  subagent fix loops ≤ 5 rounds.
- Compaction instruction: "when compacting, preserve mode, stop-condition, modified files,
  verification commands run, open questions".
- Evidence-in-recap contract: each item VERIFIED / NOT VERIFIED / BLOCKED with the command.

### E. Bundle generalized agents
phase-lead / worker / drone from `~/.claude/agents`, WSL rule replaced by "repeat the repo's
off-limits list", `skills:` preloading a slim `subagent-rules` skill, `memory: project`.

### F. Templates in assets/
CLAUDE.md, docs/status.md, docs/log.md, subagent brief, recap, question batch, handoff.

### G. Always-on bridge
A ~15-line `~/.claude/CLAUDE.md` with the 5 hard rules and "invoke gobind-working-style at
session start". Skills only load when triggered; this guarantees the floor.

### H. Testing
Pressure-test evals (time + sunk cost + authority) for git, questions, dev server, done-gate;
run with and without the skill; description trigger loop; `claude plugin validate`.

## 3. Sources (primary)
- https://code.claude.com/docs/en/hooks , /skills , /plugins , /plugins-reference , /sub-agents , /memory , /best-practices
- https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more
- https://github.com/obra/superpowers (writing-skills, verification-before-completion, systematic-debugging)
- https://github.com/DietrichGebert/ponytail , https://github.com/JuliusBrussee/caveman , https://github.com/hardikpandya/stop-slop
- https://github.com/mattpocock/skills (git-guardrails), https://github.com/karanb192/claude-code-hooks , https://github.com/GWUDCAP/cc-sessions , https://github.com/MarcinSufa/claude-handoff
- https://github.com/anthropics/claude-plugins-official (hookify, claude-md-management, ralph-loop)
- arxiv 2507.11538 (IFScale), 2608.12426 (constraint saturation), 2603.23530 (prospective memory), 2605.01771 (compliance gap), 2604.07192 (constraint encoding), 2605.10039 (CLAUDE.md factorial study)
- https://www.humanlayer.dev/blog/writing-a-good-claude-md

## 4. Build log, 2026-09-15

Built as the `gobind` plugin (see README). Verification:

- `bash tests/run.sh`: 83 hook cases pass (git-guard with and without grant, secrets, server,
  question gate, auto mode switch, config/test guards, docs nudge, gate tracker, done gate,
  session index).
- `claude plugin validate .`: passes.
- End-to-end with `claude -p --plugin-dir`: `git commit` denied by git-guard, `.env` read denied
  by secrets-guard, `/gobind:mode autonomous <stop-condition>` wrote the state file.
- Trigger check: on the query "the theme switcher ... is stuck bottom left ... i have pnpm dev
  running already" a fresh `claude -p` session invoked `gobind:working-style` on its own.
- skill-creator `run_loop` description optimizer reported 4/8 on the held-out set, but every
  query (positives included) scored 0.0 because the harness only counts a temporary copy of
  the skill it writes into `.claude/commands/`, and the model invoked the real installed plugin
  skill instead. Treat that number as void; the description was kept as written. To re-run the
  optimizer honestly, disable the plugin first (`claude plugin disable gobind@skills-dir`).

Not verified in a live interactive session: the Stop hook (done-gate) and the AskUserQuestion
gate. Both pass unit tests. Watch them on the first real autonomous run.
