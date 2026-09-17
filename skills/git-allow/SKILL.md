---
name: git-allow
description: Grant the agent git write access on one feature branch for this session (commit, push, branch ops on that branch). main and master stay locked. Run when Gobind says /gobind:git-allow <branch> or "you own the branch".
argument-hint: "<branch|*>"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/state.sh *)
---

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/state.sh "${CLAUDE_SESSION_ID}" git-allow "$0" 2>&1 || true`
```

If the block above shows an error, run `"${CLAUDE_PLUGIN_ROOT}/scripts/state.sh" "${CLAUDE_SESSION_ID}" git-allow $0` with the Bash tool.

With the grant: commit often with clear messages, one commit per logical chunk, push to origin after each verified step. Still never: commit or push on main/master, merge into main, force-push, `git add -f` a binary or ignored file. The grant ends with the session; say "git locked" in your recap if you want Gobind to know.
