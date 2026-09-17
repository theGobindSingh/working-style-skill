---
name: recap
description: Give Gobind the short status he asks for with "what's done, what's remaining", "status?", "where are we", "give me a short summary", or /gobind:recap. Use it whenever he asks for progress, even informally.
argument-hint: "[full]"
---

Current session state:

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/state.sh "${CLAUDE_SESSION_ID}" show 2>&1 || true`
```

Answer in this shape and nothing else, unless `$ARGUMENTS` is `full`:

```
Done: <one line, with what verified it>
Remaining: <one line>
Blocked: <one line, or "nothing">
```

Bad news first. No preamble, no headers, no restating the task. If an estimate was asked for, add one line: `Estimate: <time>`, based on what is actually left, not optimism.

For `full`, use the recap template at `${CLAUDE_PLUGIN_ROOT}/assets/templates/recap.md.template`: outcome in one line, then a table of items marked VERIFIED (with the command or evidence), NOT VERIFIED, or BLOCKED, then assumptions taken, then what is left. Detail beyond that goes into docs/status.md, not the chat.
