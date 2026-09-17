---
name: test-allow
description: Allow the agent to skip, focus or delete tests this session (the test-guard hook otherwise asks). Run when Gobind says /gobind:test-allow.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/state.sh *)
---

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/state.sh "${CLAUDE_SESSION_ID}" test-allow 2>&1 || true`
```

Test edits that skip or delete are allowed this session. Say which tests you touch and why in the recap.
