---
name: git-lock
description: Revoke the agent's git write grant so git is read-only again this session. Run when Gobind says /gobind:git-lock or "stop touching git".
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/state.sh *)
---

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/state.sh "${CLAUDE_SESSION_ID}" git-lock 2>&1 || true`
```

Git is read-only again: status, log, diff, show, blame only. Confirm in one line.
