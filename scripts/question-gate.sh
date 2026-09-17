#!/usr/bin/env bash
# =============================================================================
# question-gate.sh - PreToolUse(AskUserQuestion) hook: no questions while away
# =============================================================================
#
# PreToolUse(AskUserQuestion): in autonomous mode Gobind is away. Questions are denied unless
# they are the stop-condition he named (tag them [stop-condition]).
#
# WHY
#   In autonomous mode nobody is there to answer, so a question stalls the
#   work until the user returns. This hook turns such a question back into a
#   decision the agent must make and record.
#
# DECISION TABLE
#   mode is collab                                  -> no objection
#   mode is autonomous, question text or header
#     contains [stop-condition] or [stopcondition]  -> no objection
#   mode is autonomous, anything else               -> deny, with a reason
#                                                      that tells the agent
#                                                      to decide, record the
#                                                      assumption, and how to
#                                                      tag a real stop-
#                                                      condition question
#
# INPUT FIELDS USED
#   .tool_input.questions[].question   the question text
#   .tool_input.questions[].header     the short chip label
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Only autonomous mode restricts questions. `allow` exits the script, so
# nothing below runs in collab mode.
MODE="$(state_get '.mode')"
[ "$MODE" = "autonomous" ] || allow

# Gather every question text and header into one space-separated string.
#   []?  iterate the array, without an error if it is missing
#   .x?  read a field, without an error if the element is not an object
TXT="$(printf '%s' "$INPUT" | jq -r '[.tool_input.questions[]?.question?, .tool_input.questions[]?.header?] | join(" ")' 2>/dev/null)"

# The agent can mark a question as the named stop-condition by writing
# [stop-condition] in it. -i ignores case; "-?" makes the hyphen optional.
printf '%s' "$TXT" | grep -Eiq '\[stop-?condition\]' && allow

# Build the denial. Include the stop-condition so the agent can judge whether
# its question really is that case, and the time autonomous mode began.
SC="$(state_get '.stop_condition')"; SET="$(state_get '.set_at')"
# When the user named no stop-condition, spell out the default bar for when
# stopping is justified.
[ -z "$SC" ] && SC="none named; only stop if the result he sees would change materially or something is hard to reverse"
deny "question-gate: autonomous mode is on (since $SET). Gobind is away and said not to ask. Decide it yourself now, pick the sensible default, and record the assumption in docs/status.md and the final recap. Stop-condition: $SC. If this question IS that stop-condition, ask again with [stop-condition] in the question text."
