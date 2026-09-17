#!/usr/bin/env bash
# =============================================================================
# docs-nudge.sh - PostToolUse(Edit|Write|MultiEdit) hook: count edits, nudge docs
# =============================================================================
#
# PostToolUse(Edit|Write|MultiEdit): count source edits; after 8 without touching the state
# doc, nudge once. Also feeds the done-gate.
#
# WHY
#   The project's state doc (docs/status.md or docs/STATE.md) should record
#   decisions and progress as they happen, not in a rush at the end. This
#   hook counts edits to source files and reminds the agent when the doc has
#   fallen behind.
#
# CLASSIFICATION OF THE EDITED FILE (path relative to the project root)
#   State and agent docs: docs/status.md, docs/STATE.md, docs/log.md,
#     docs/PROGRESS.md, CLAUDE.md, AGENTS.md, anything under .claude/, and
#     any nested CLAUDE.md
#       -> reset edits_since_docs to 0; the docs are being kept current
#   Non-source files: other *.md, *.txt, *.json, *.lock, *.yaml, *.yml,
#     .gitignore
#       -> ignored; neither counted nor resetting
#   Anything else counts as source
#       -> source_edits += 1 and edits_since_docs += 1
#
# NUDGES
#   When a state doc exists and edits_since_docs reaches exactly 8, 20 or 40,
#   the hook adds a reminder to the model's context. Hitting exact values
#   means each threshold nudges once instead of on every later edit.
#
# CONSUMERS
#   done-gate.sh reads source_edits and edits_since_docs at the end of an
#   autonomous session.
#
# NOTE
#   Each edit tool call counts once, so editing one file three times adds 3.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Absolute path of the file that was just edited. Nothing to do without one.
FP="$(jget '.tool_input.file_path')"; [ -z "$FP" ] && exit 0

# Strip the "<project>/" prefix to get a project-relative path. A file outside
# the project keeps its absolute path and so never matches the doc patterns.
REL="${FP#$PROJECT_DIR/}"

# Classify the path. Case patterns are tried top to bottom, and `*` in a case
# pattern also matches "/".
case "$REL" in
  # State and agent docs: reset the since-docs counter and stop.
  # There is no state_init here. If the state file does not exist, jq fails,
  # mv is skipped, and nothing changes, which is harmless.
  docs/status.md|docs/STATE.md|docs/log.md|docs/PROGRESS.md|CLAUDE.md|AGENTS.md|.claude/*|*/CLAUDE.md)
    t="$(mktemp)"; jq '.edits_since_docs=0' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"; exit 0;;
  # Other docs, data and config files are not source code. Ignore them.
  *.md|*.txt|*.json|*.lock|*.yaml|*.yml|.gitignore|*/.gitignore) exit 0;;
esac

# Everything else is a source edit. Increase both counters in one update.
state_init
t="$(mktemp)"; jq '.source_edits+=1 | .edits_since_docs+=1' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"

# Read the new since-docs count to decide whether to nudge.
N="$(state_get '.edits_since_docs')"

# Nudge only in projects that have a state doc, and only at the thresholds.
if [ -f "$PROJECT_DIR/docs/status.md" ] || [ -f "$PROJECT_DIR/docs/STATE.md" ]; then
  if [ "$N" = "8" ] || [ "$N" = "20" ] || [ "$N" = "40" ]; then
    # additionalContext on a PostToolUse hook is shown to the model next to
    # the tool result.
    jq -cn --arg c "[gobind] $N source files edited since the state doc (docs/status.md or docs/STATE.md) was last touched. If a decision, blocker or finished piece happened, rewrite the stale lines there now (ISO timestamp from date -Iseconds), not at the end." '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
  fi
fi
exit 0
