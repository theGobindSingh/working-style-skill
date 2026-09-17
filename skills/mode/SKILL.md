---
name: mode
description: Switch or show the agent's working mode for this session (autonomous or collab) and the stop-condition. Run when Gobind says /gobind:mode, "autonomous", "collab", "normal mode", or wants to see the current mode.
argument-hint: "[autonomous|collab|status] [stop-condition text]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/state.sh *)
---

Result of the request `$ARGUMENTS`:

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/state.sh "${CLAUDE_SESSION_ID}" $(case "$0" in autonomous|auto|collab|collaborative|normal) echo set-mode;; *) echo show;; esac) $ARGUMENTS 2>&1 || true`
```

If the block above shows an error, run the same command yourself with the Bash tool:
`"${CLAUDE_PLUGIN_ROOT}/scripts/state.sh" "${CLAUDE_SESSION_ID}" set-mode <mode> [stop-condition]`.

What each mode means:

- **autonomous**: Gobind is away. Ask everything you still need right now in one numbered batch (recommendation and stakes per question), then no more questions; AskUserQuestion is denied by a hook unless the question text carries `[stop-condition]` and it really is the stop-condition. Take engineering decisions yourself and record them in docs/status.md under "Decisions taken without asking". Content, product and gameplay calls get a placeholder or the stop-condition. The Stop hook will not let the session end with unverified source edits or a stale status doc. Finish with a recap marking each item VERIFIED / NOT VERIFIED / BLOCKED.
- **collab**: propose a short change list before non-trivial work, wait for a go, one step at a time. Trivial edits: just do them.

Confirm the mode in one line and continue with the task at hand.
