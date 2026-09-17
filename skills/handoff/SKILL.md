---
name: handoff
description: Write a handoff into docs/status.md so the next session (or Gobind in the morning) can resume without re-deriving anything. Use when Gobind says /gobind:handoff, "write a handoff", "i'm stopping here", when finishing an autonomous run, or when context is about to compact mid-task.
argument-hint: "[note]"
---

Repo state right now:

```
!`git status --short 2>/dev/null | head -20; echo "branch: $(git symbolic-ref --short -q HEAD 2>/dev/null)"; date -Iseconds`
```

1. Read `docs/status.md` if it exists (create it from `${CLAUDE_PLUGIN_ROOT}/assets/templates/status.md.template` if not, and mention that you did).
2. Rewrite the "Now", "Blocked" and "Next up" sections so they describe the repo as it is at this moment. Rewrite stale lines; do not append history there.
3. Fill the "Handoff" section from `${CLAUDE_PLUGIN_ROOT}/assets/templates/handoff.md.template`: goal, current state, numbered next steps, constraints, gotchas, exact commands to resume. Include `$ARGUMENTS` if given. Redact any secret; name the variable, never the value.
4. Add one entry at the top of `docs/log.md` (newest first) if a decision, blocker or finished piece happened since the last entry. Skip trivia.
5. Every timestamp is full ISO 8601 with offset from `date -Iseconds`.
6. Reply with three lines: where the handoff is, the first next step, and anything Gobind must do himself (git, secrets, approvals).

Do not commit. Git is his.
