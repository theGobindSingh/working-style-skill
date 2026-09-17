#!/usr/bin/env bash
# =============================================================================
# done-gate.sh - Stop hook: do not finish autonomous work unverified
# =============================================================================
#
# Stop: in autonomous mode, do not let the session end with unverified source changes or a
# stale state doc. Blocks at most twice per session, never when already inside a block.
#
# WHEN IT RUNS
#   Every time the agent is about to end its turn (the Stop event).
#
# HOW BLOCKING WORKS
#   Printing {"decision":"block","reason":"..."} makes Claude Code keep the
#   agent working, with the reason given to it as the next instruction.
#   Printing nothing lets the agent stop normally.
#
# THE CHECKS, IN ORDER. The first one that fails ends the script silently.
#   1. The mode must be autonomous. In collab mode the user is present.
#   2. stop_hook_active must not be true. Claude Code sets it when the agent
#      is already continuing because of a Stop hook. Blocking again then
#      could loop forever.
#   3. stop_blocks must be below 2. After two blocks the hook gives up, so a
#      task that truly cannot be verified still ends.
#   4. At least one source file must have been edited. Pure research or
#      docs-only sessions have nothing to verify.
#   Then it collects reasons to block:
#     a. No gate passed: .gates_ran is empty. gate-tracker.sh records only
#        gate commands that did not fail.
#     b. The state doc is stale: source edits happened since the last change
#        to docs/status.md or docs/STATE.md (see docs-nudge.sh). This only
#        applies when one of those files exists in the project.
#   No reasons means the session may stop. Otherwise stop_blocks is increased
#   and the block decision is printed.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Check 1: only autonomous sessions are gated.
MODE="$(state_get '.mode')"
[ "$MODE" = "autonomous" ] || exit 0

# Check 2: never block while already continuing because of a Stop hook.
[ "$(jget '.stop_hook_active')" = "true" ] && exit 0

# Check 3: at most two blocks per session. ${BLOCKS:-0} treats an unreadable
# value as zero so the numeric comparison cannot fail.
BLOCKS="$(state_get '.stop_blocks')"; [ "${BLOCKS:-0}" -ge 2 ] && exit 0

# Check 4: nothing to verify unless source files changed.
EDITS="$(state_get '.source_edits')"; [ "${EDITS:-0}" -gt 0 ] || exit 0

# Gates seen so far as "lint,test", or "" when none ran.
GATES="$(state_get '.gates_ran | join(",")')"
# Source edits since the state doc was last touched.
SINCE="$(state_get '.edits_since_docs')"

# $reasons accumulates bullet lines. Each reason begins with a newline, so
# the final message shows one "- ..." bullet per line.
reasons=""

# Reason a: source changed but no verification gate passed.
[ -z "$GATES" ] && reasons="$reasons
- No verification gate passed this session (no successful lint / typecheck / build / test command seen) while $EDITS source files changed. Run the repo's real gates now and report the actual output."

# Reason b: the state doc exists but did not follow the latest edits. Projects
# without a state doc are never blocked for this.
if [ "${SINCE:-0}" -gt 0 ] && { [ -f "$PROJECT_DIR/docs/status.md" ] || [ -f "$PROJECT_DIR/docs/STATE.md" ]; }; then
  reasons="$reasons
- docs/status.md (or STATE.md) was not updated after $SINCE source edits. Rewrite the stale lines with an ISO timestamp (date -Iseconds) and note assumptions you took."
fi

# Everything checks out: let the session stop.
[ -z "$reasons" ] && exit 0

# Count this block, using the same safe temp-file update as state_set, so
# check 3 eventually lets the session end.
t="$(mktemp)"; jq '.stop_blocks+=1' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"

# Print the block decision. The reason lists what is missing and how the final
# recap must label each item. jq --arg escapes the multi-line text safely.
jq -cn --arg r "[gobind done-gate] Autonomous mode: not done yet.$reasons
Then finish with a recap where every item is marked VERIFIED (with the command/evidence), NOT VERIFIED, or BLOCKED." '{decision:"block",reason:$r}'
exit 0
