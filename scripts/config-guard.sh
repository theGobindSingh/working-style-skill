#!/usr/bin/env bash
# =============================================================================
# config-guard.sh - PreToolUse(Edit|Write|MultiEdit|Bash) hook: protect the guards
# =============================================================================
#
# PreToolUse(Edit|Write|MultiEdit|Bash): the agent must not silently loosen the guards that
# constrain it. Editing settings/hooks/plugin scripts asks first.
#
# WHY
#   Every other guard is pointless if the agent can edit it away. Changes to
#   permissions, hook registration, plugin metadata, the guard scripts or the
#   session state therefore need a human's approval. `ask` is used rather
#   than `deny`, since the user may legitimately want such a change.
#
# PROTECTED FOR EDIT / WRITE / MULTIEDIT (the GUARDED regex)
#   .claude/settings.json, .claude/settings.local.json   permissions and hooks
#   hooks/hooks.json                                     plugin hook registration
#   anything under .claude-plugin/                       plugin manifest
#   scripts/git-guard.sh, secrets-guard.sh, server-guard.sh,
#     config-guard.sh, test-guard.sh                     the guards themselves
#   scripts/question-gate.sh, done-gate.sh, lib.sh       gates and shared code
#   anything under .claude/gobind/                       session state files
#   Not protected: state.sh, prompt-reminder.sh, session-index.sh,
#   gate-tracker.sh and docs-nudge.sh.
#
# PROTECTED FOR BASH
#   A command asks when rm, mv, truncate, >, sed -i or tee appears before a
#   mention of .claude/gobind, .claude/settings, hooks/hooks.json or
#   .claude-plugin, with no |, ; or & in between. The guard scripts
#   themselves are not covered on the Bash side.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Paths whose modification must be confirmed by a human. Each (^|/) makes the
# name match only as a whole path component, so "myhooks/hooks.json" does
# not count.
GUARDED='(^|/)\.claude/settings(\.local)?\.json$|(^|/)hooks/hooks\.json$|(^|/)\.claude-plugin/|(^|/)scripts/(git|secrets|server|config|test)-guard\.sh$|(^|/)scripts/(question-gate|done-gate|lib)\.sh$|(^|/)\.claude/gobind/'

case "$TOOL_NAME" in
  # File editing tools: check the target path.
  Edit|Write|MultiEdit)
    FP="$(jget '.tool_input.file_path')"; [ -z "$FP" ] && allow
    printf '%s' "$FP" | grep -Eq "$GUARDED" && ask "config-guard: $FP changes the hooks or permissions that constrain this agent. Gobind decides that, not the agent. Confirm with him."
    allow;;
  # Shell commands: look for a destructive or writing command aimed at a
  # guarded location. [^|;&]* keeps the match inside one simple command.
  Bash)
    CMD="$(jget '.tool_input.command')"; [ -z "$CMD" ] && allow
    printf '%s' "$CMD" | grep -Eq '(rm|mv|truncate|>|sed -i|tee)[^|;&]*(\.claude/gobind|\.claude/settings|hooks/hooks\.json|\.claude-plugin)' && ask "config-guard: that command alters the agent's own guards or state. Confirm with Gobind first."
    allow;;
esac
# Any other tool: no objection.
allow
