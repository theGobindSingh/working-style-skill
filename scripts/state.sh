#!/usr/bin/env bash
# =============================================================================
# state.sh - command-line interface to the per-session Gobind state file
# =============================================================================
#
# PURPOSE
#   The hook scripts keep per-session settings and counters in
#   <project>/.claude/gobind/session-<session_id>.json (field reference: see
#   the "state" section of lib.sh). This script is the way to read and change
#   that file from outside a hook. The plugin's slash commands call it, and
#   so does tests/run.sh.
#
#   It does NOT source lib.sh. lib.sh reads hook JSON from stdin, which would
#   make this CLI wait for input. The paths are therefore resolved again below,
#   in exactly the same way.
#
# CLI for the per-session state used by the hooks. Called from slash commands.
#   state.sh <session_id> show
#   state.sh <session_id> set-mode autonomous|collab [stop condition text...]
#   state.sh <session_id> git-allow <branch|*>
#   state.sh <session_id> git-lock
#   state.sh <session_id> test-allow
#
# COMMANDS IN DETAIL
#   show
#       Print a human-readable summary of the session state.
#   set-mode <mode> [stop condition text...]
#       Switch between the two working modes.
#         autonomous (alias: auto)                 the user is away; the agent
#                                                  must not ask questions
#         collab (aliases: collaborative, normal)  the default; propose first
#       Every word after the mode becomes the stop-condition: the one
#       situation in which the agent may still ask while autonomous.
#   git-allow <branch|*>
#       Let the agent commit, push and so on while on <branch>, or on any
#       branch with "*". Protected branches stay locked (see git-guard.sh).
#   git-lock
#       Remove the git grant, making git read-only again.
#   test-allow
#       Stop test-guard.sh from asking about skipped, focused or deleted tests
#       for the rest of this session.
#
# EXIT STATUS
#   0 on success. 1 for an unknown command, an unknown mode, or a missing
#   branch argument. Confirmations go to stdout and errors go to stderr.
#
# ENVIRONMENT
#   CLAUDE_PROJECT_DIR  project root; defaults to the current directory
# =============================================================================

# Treat unset variables as errors. `set -e` is not used; each command below
# handles its own failure.
set -u

# First argument: the session id, "default" when missing. `shift` drops it so
# that $1 becomes the command. `|| true` avoids an error when there were no
# arguments at all.
SESSION_ID="${1:-default}"; shift || true

# Second argument: the command, "show" when missing. After this shift, $@
# holds only the command's own arguments.
CMD="${1:-show}"; shift || true

# Resolve file locations exactly like lib.sh does, so this CLI and the hooks
# always read and write the same file.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_DIR="$PROJECT_DIR/.claude/gobind"
STATE_FILE="$STATE_DIR/session-${SESSION_ID}.json"

# Create the state directory. Unlike in lib.sh, errors are not hidden here: a
# person running the CLI should see why it failed.
mkdir -p "$STATE_DIR"

# Create the default state document if this session has none yet.
# This JSON literal must stay identical to the one in lib.sh's state_init.
[ -f "$STATE_FILE" ] || printf '{"mode":"collab","stop_condition":"","git_grant":"","test_grant":false,"set_at":"%s","source_edits":0,"edits_since_docs":0,"gates_ran":[],"stop_blocks":0,"auto_detected":false}\n' "$(date -Iseconds)" > "$STATE_FILE"

# Dispatch on the command.
#
# Every command that changes state uses the same safe-update pattern:
#
#     t="$(mktemp)"; jq '<update>' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"
#
# jq writes the new document to a temporary file, and that file replaces the
# state file only if jq succeeded. A failed update therefore cannot empty the
# state file. On failure the temporary file is simply left in the temp dir.
case "$CMD" in
  # show
  #   Turn the JSON into labelled lines using jq string interpolation, \( ... ).
  #   Empty values get friendly text instead of a blank:
  #     stop_condition ""   -> "(none)"
  #     git_grant ""        -> "locked (read-only)"
  #     gates_ran []        -> "(none)"   (joining an empty array gives "")
  #   tests/run.sh parses the "mode: " line, so keep that label stable.
  show)
    jq -r '"mode: \(.mode)\nstop-condition: \(.stop_condition | if .=="" then "(none)" else . end)\ngit grant: \(.git_grant | if .=="" then "locked (read-only)" else . end)\ntest grant: \(.test_grant)\nset at: \(.set_at)\nsource edits: \(.source_edits), since docs touched: \(.edits_since_docs)\ngates run: \(.gates_ran | join(", ") | if .=="" then "(none)" else . end)"' "$STATE_FILE" ;;
  # set-mode <mode> [stop condition words...]
  set-mode)
    # Take the mode word, defaulting to collab. The remaining words, joined
    # with single spaces by "$*", form the stop-condition text.
    MODE="${1:-collab}"; shift || true; SC="$*"
    # Map every accepted alias onto one of the two canonical names that the
    # hooks compare against. Anything else is rejected with exit status 1.
    case "$MODE" in autonomous|auto) MODE=autonomous;; collab|collaborative|normal) MODE=collab;; *) echo "unknown mode: $MODE" >&2; exit 1;; esac
    # Store the mode, the stop-condition and the time of the change. Also:
    #   auto_detected=false  the mode was set explicitly, not from a phrase
    #   stop_blocks=0        give done-gate.sh a fresh budget of two blocks
    # --arg passes shell values into jq as properly escaped strings.
    t="$(mktemp)"; jq --arg m "$MODE" --arg s "$SC" --arg t "$(date -Iseconds)" '.mode=$m | .stop_condition=$s | .set_at=$t | .auto_detected=false | .stop_blocks=0' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"
    # Confirm. The inner $( ... ) adds " (stop-condition: ...)" only when a
    # stop-condition was given.
    echo "mode set to $MODE$( [ -n "$SC" ] && echo " (stop-condition: $SC)")" ;;
  # git-allow <branch|*>
  git-allow)
    # A branch argument is required. Without one, print usage and exit 1.
    BR="${1:-}"; [ -z "$BR" ] && { echo "usage: git-allow <branch|*>" >&2; exit 1; }
    # Record the grant. git-guard.sh reads .git_grant on every git command.
    t="$(mktemp)"; jq --arg b "$BR" '.git_grant=$b' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"
    echo "git grant: $BR (main/master stay locked)" ;;
  # git-lock
  #   An empty grant means read-only git.
  git-lock)
    t="$(mktemp)"; jq '.git_grant=""' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"; echo "git locked: read-only" ;;
  # test-allow
  #   There is no matching "test-lock"; the grant lasts until the session's
  #   state file is removed.
  test-allow)
    t="$(mktemp)"; jq '.test_grant=true' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"; echo "test edits allowed this session" ;;
  # Anything else is a usage error.
  *) echo "unknown command: $CMD" >&2; exit 1 ;;
esac
