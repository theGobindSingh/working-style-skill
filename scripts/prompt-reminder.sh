#!/usr/bin/env bash
# =============================================================================
# prompt-reminder.sh - UserPromptSubmit hook: mode reminder and phrase switching
# =============================================================================
#
# UserPromptSubmit: timestamp + mode on every turn (trailing reminder), and automatic mode
# switching from Gobind's own phrases.
#
# WHEN IT RUNS
#   Each time the user submits a message, before the model sees it.
#
# WHAT IT DOES
#   1. Mode switching from natural phrases:
#        - Phrases such as "going to sleep", "full autonomous", "don't ask me
#          questions" or "when I wake up" switch collab -> autonomous. A
#          stop-condition is pulled from the same message when one is phrased
#          like "only ask if gameplay is affected".
#        - Phrases such as "I'm back", "normal mode" or "you can ask again"
#          switch autonomous -> collab and clear the stop-condition.
#      A switch only happens when the mode actually changes, so repeating
#      the phrase does not overwrite the stored stop-condition or timestamp.
#   2. On every message, add one context line for the model with the time
#      and current mode, plus a mode-specific reminder. After a switch, a
#      second line explains what the new mode requires.
#
# OUTPUT
#   {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit",
#                          "additionalContext":"<lines>"}}
#   Claude Code appends additionalContext to the model's context for this
#   turn. The user's message itself is not changed.
#
# MATCHING NOTES
#   - Matching runs on a lower-cased copy of the message. The stop-condition
#     is taken from the original text, so its capitalisation is kept.
#   - The autonomous phrases are tested first. A message containing both
#     kinds of phrase therefore switches to, or stays in, autonomous mode.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# The user's message, and a lower-case copy for case-insensitive matching.
P="$(jget '.prompt')"
LP="$(printf '%s' "$P" | tr '[:upper:]' '[:lower:]')"

# Current mode. state_get also creates the state file on a new session, which
# the later updates depend on.
MODE="$(state_get '.mode')"

# Extra explanation shown only when this message changes the mode.
note=""

# ---- phrases that turn autonomous mode ON -----------------------------------
# Alternatives in the regex, in order:
#   full autonomous / full-autonomous / fullautonom...
#   autonomous mode
#   going to sleep / goin to bed / ...
#   i'm going to sleep / im going to sleep
#   don't ask (me) (any) questions / dont ask ...
#   no questions
#   take (most|all) decisions on your own / yourself
#   when i wake up
#   while i'm away / gone / out / asleep
#   until finished / until it's finished
# In the double-quoted pattern, ' is an ordinary character; "'?" makes the
# apostrophe optional so "im" and "i'm" both match.
if printf '%s' "$LP" | grep -Eq "full[ -]?autonom|autonomous mode|goin(g)? to (sleep|bed)|i'?m going to sleep|im going to sleep|don'?t ask (me )?(any )?questions|dont ask (me )?(any )?questions|no questions|take (most |all )?decisions (on your own|yourself)|when i wake up|while i'?m (away|gone|out|asleep)|until (it'?s )?finished"; then
  # Only act on a real change, so the original stop-condition and set_at
  # survive a repeated phrase.
  if [ "$MODE" != "autonomous" ]; then
    # Extract a stop-condition from the original message. Two shapes, up to
    # the next "." or ";":
    #   (only|unless|except) ... (ask|wait|stop|check) ...
    #       e.g. "only ask if gameplay is affected"
    #   (ask|wait|stop|check) ... [only] if ...
    #       e.g. "stop if the API contract changes"
    # -o prints only the matched part, -i ignores case, head -1 keeps the
    # first match. The result is "" when the message names no condition.
    sc="$(printf '%s' "$P" | grep -oiE '(only|unless|except)[^.;]*(ask|wait|stop|check)[^.;]*|(ask|wait|stop|check)[^.;]* (only )?if[^.;]*' | head -1)"
    state_init
    # Switch to autonomous. auto_detected=true records that a phrase, not a
    # slash command, caused it. stop_blocks=0 gives done-gate.sh a fresh budget.
    t="$(mktemp)"; jq --arg s "$sc" --arg t "$(now_iso)" '.mode="autonomous" | .auto_detected=true | .set_at=$t | .stop_condition=$s | .stop_blocks=0' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"
    MODE=autonomous
    # Tell the model how to behave from now on. All remaining questions go
    # in one batch now, because question-gate.sh will deny later ones.
    note="Mode switched to AUTONOMOUS from this message. Ask every remaining question NOW in one numbered batch (recommendation + stakes each), then no more questions; AskUserQuestion will be denied. Take engineering decisions yourself; content/product/gameplay calls get a placeholder or the stop-condition. Finish, verify, update docs/status.md, recap with VERIFIED / NOT VERIFIED / BLOCKED per item."
  fi
# ---- phrases that turn autonomous mode OFF ----------------------------------
# i'm back / im back, normal mode, collab mode / collaborative mode,
# stop autonomous, you can ask (me) now / again, ask me things / questions again
elif printf '%s' "$LP" | grep -Eq "i'?m back|im back|normal mode|collab(orative)? mode|stop autonomous|you can ask (me )?(now|again)|ask me (things|questions) again"; then
  # Only switch when currently autonomous.
  if [ "$MODE" = "autonomous" ]; then
    # Back to collab; clear the stop-condition since it no longer applies.
    # The file is guaranteed to exist because state_get ran above.
    t="$(mktemp)"; jq --arg t "$(now_iso)" '.mode="collab" | .auto_detected=false | .set_at=$t | .stop_condition=""' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"
    MODE=collab; note="Mode switched back to COLLABORATIVE: propose before non-trivial changes, one step at a time."
  fi
fi

# ---- per-turn context line --------------------------------------------------
# Re-read the stop-condition, since it may have just been set above.
SC="$(state_get '.stop_condition')"
# Common prefix: timestamp and mode.
line="[gobind] $(now_iso) | mode: $MODE"
# Mode-specific reminder appended to the same line.
[ "$MODE" = "autonomous" ] && line="$line | no questions (stop-condition: ${SC:-none named})"
[ "$MODE" = "collab" ] && line="$line | propose before non-trivial work; git read-only; short reply, outcome first"
# After a switch, add the explanation as a second line.
[ -n "$note" ] && line="$line
[gobind] $note"

# Emit the context for Claude Code. jq --arg escapes quotes and newlines.
jq -cn --arg c "$line" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
exit 0
