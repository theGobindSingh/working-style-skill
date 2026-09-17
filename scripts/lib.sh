#!/usr/bin/env bash
# =============================================================================
# lib.sh - shared helpers for every Gobind hook script
# =============================================================================
#
# PURPOSE
#   Every hook script in scripts/ starts with:
#
#       source "$(dirname "$0")/lib.sh"
#
#   Shared helpers for every hook. Source this; never execute it.
#   Sourcing this file does three things:
#     1. Reads the hook event JSON that Claude Code writes to the hook's stdin
#        and keeps it in $INPUT.
#     2. Derives the values almost every hook needs: session id, working
#        directory, project directory, state file path and tool name.
#     3. Defines small helper functions:
#          jget               read one field out of the input JSON
#          state_init/get/set create, read and update the session state file
#          deny / ask / allow emit a PreToolUse permission decision and exit
#          current_branch     name of the checked-out git branch
#          is_main_branch     is a branch one of the protected trunk names
#          segments           split a shell command line into simple commands
#
# HOW CLAUDE CODE TALKS TO A HOOK
#   Input:  one JSON object on stdin. Fields used by these scripts include
#           session_id, cwd, hook_event_name, tool_name, tool_input, prompt,
#           source and stop_hook_active.
#   Output: exit status 0, plus optional JSON on stdout. An empty stdout means
#           "no objection". For PreToolUse, JSON with
#           hookSpecificOutput.permissionDecision = "deny" or "ask" blocks the
#           tool call or asks the human to approve it.
#
# DEPENDENCIES
#   bash, jq, coreutils (cat, date, mkdir, mktemp, mv, rm), GNU sed, and git
#   for the git helpers.
#
# FAILURE PHILOSOPHY
#   A hook must never break the agent's session. Nearly every command below
#   discards errors (2>/dev/null, || true). A missing tool or malformed input
#   therefore degrades to "no objection" instead of a crashing hook.
# =============================================================================

# Treat any use of an unset variable as an error, which catches typos in
# variable names. `set -e` is deliberately NOT used: many commands in the hooks
# are expected to fail quietly, for example a grep that finds no match.
set -u

# Read all of stdin, the hook event JSON, into one string. If stdin is closed
# or unreadable, fall back to an empty string instead of failing.
# Because of this line, sourcing lib.sh from an interactive terminal would wait
# for input. That is why state.sh, a normal CLI, does not source it.
INPUT="$(cat 2>/dev/null || true)"

# -----------------------------------------------------------------------------
# jget <jq-path>
#   Print one value from the hook input JSON as a raw string.
#
#   Example:
#       jget '.tool_input.command'      prints: git status
#
#   Details:
#     -r          print strings without the surrounding JSON quotes
#     // empty    turn null or a missing key into no output at all, so callers
#                 get "" rather than the literal word "null"
#     2>/dev/null invalid JSON or a bad path also yields "" instead of an error
# -----------------------------------------------------------------------------
# jget '.tool_input.command'  -> raw string ("" when missing/null)
jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# Unique id of the Claude Code session that fired this hook. Each session gets
# its own state file, so two sessions in one project never overwrite each
# other's mode or grants.
SESSION_ID="$(jget '.session_id')"

# Directory the tool call runs in, as reported by Claude Code.
CWD="$(jget '.cwd')"
# When the input has no cwd, for example during manual testing, use the
# shell's own working directory.
[ -z "$CWD" ] && CWD="$PWD"

# Root of the project. Claude Code exports CLAUDE_PROJECT_DIR to hooks. When it
# is absent, as in some manual runs, fall back to the working directory.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"

# Directory that holds one state file per session: <project>/.claude/gobind/
STATE_DIR="$PROJECT_DIR/.claude/gobind"

# This session's state file. Without a session id, every caller shares
# session-default.json.
STATE_FILE="$STATE_DIR/session-${SESSION_ID:-default}.json"

# Tool that is about to run (PreToolUse) or just ran (PostToolUse), such as
# Bash, Edit, Write or Read. Empty for events that are not about a tool, such
# as SessionStart, UserPromptSubmit and Stop.
TOOL_NAME="$(jget '.tool_name')"

# now_iso
#   Print the current local time in ISO 8601 with seconds and UTC offset,
#   for example 2026-09-15T06:16:02+05:30. Used for every timestamp in state.
now_iso() { date -Iseconds; }

# ---- state -------------------------------------------------------------
# The state file is a small JSON document describing one session:
#
#   mode              "collab" (the default) or "autonomous"
#   stop_condition    free text naming the one situation in which the agent
#                     may still ask a question while autonomous; "" = none
#   git_grant         "" = git is read-only; a branch name or "*" = the agent
#                     may change git state on that branch (main stays locked)
#   test_grant        true = test-guard.sh stops asking about skipped or
#                     deleted tests
#   set_at            ISO timestamp of the most recent mode change
#   source_edits      source files edited this session (docs-nudge.sh)
#   edits_since_docs  source edits since the state doc was last touched
#                     (docs-nudge.sh)
#   gates_ran         unique list of verification gates seen this session,
#                     for example ["lint","test"] (gate-tracker.sh)
#   stop_blocks       how often done-gate.sh has refused to let the session
#                     stop; it gives up after 2
#   auto_detected     true when prompt-reminder.sh switched the mode because
#                     of a phrase in the user's message
#
# NOTE: state.sh writes the same default document. Keep the two JSON literals
# identical when adding or renaming a field.

# state_init
#   Make sure the state directory and this session's state file exist. A
#   missing file is created with the default document above. An existing file
#   is never overwritten, so this is safe to call any number of times.
state_init() {
  # Create .claude/gobind/ and any parents. Ignore failure, such as a
  # read-only filesystem; later reads then simply return "".
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if [ ! -f "$STATE_FILE" ]; then
    # Write the default state. The single %s receives the creation time.
    printf '{"mode":"collab","stop_condition":"","git_grant":"","test_grant":false,"set_at":"%s","source_edits":0,"edits_since_docs":0,"gates_ran":[],"stop_blocks":0,"auto_detected":false}\n' "$(now_iso)" > "$STATE_FILE" 2>/dev/null || true
  fi
}

# state_get <jq-expression>
#   Print a value from the state file as a raw string, or "" when it is null
#   or missing. Any jq expression works, not only a plain path:
#
#       state_get '.mode'                     prints: collab
#       state_get '.gates_ran | join(",")'    prints: lint,test
#
#   state_init runs first, so reading on a brand-new session never fails.
# state_get '.mode'
state_get() { state_init; jq -r "$1 // empty" "$STATE_FILE" 2>/dev/null; }

# state_set <jq-update-expression>
#   Apply a jq update to the state file and save the result.
#
#       state_set '.mode = "autonomous"'
#
#   The update never leaves a half-written or empty state file behind:
#     1. jq writes the updated document to a fresh temporary file.
#     2. Only when jq succeeds does that file replace the state file.
#     3. When jq fails, because of a bad expression or corrupt state, the
#        temporary file is deleted and the original state stays untouched.
# state_set '.mode = "autonomous"'   (jq expression)
state_set() {
  state_init
  # `local` keeps $tmp from leaking into the calling script. The declaration
  # and the assignment are split so a mktemp failure is not masked by the
  # exit status of `local`.
  local tmp; tmp="$(mktemp)"
  if jq "$1" "$STATE_FILE" > "$tmp" 2>/dev/null; then mv "$tmp" "$STATE_FILE"; else rm -f "$tmp"; fi
}

# ---- output helpers ----------------------------------------------------
# deny and ask END the hook: they print a decision and then `exit 0`.
# The exit status must be 0, because Claude Code reads the decision from the
# JSON on stdout. A non-zero status would be treated as a hook error rather
# than as a decision. Both use `jq -cn`:
#   -n        build the JSON from nothing instead of reading input
#   -c        print it on one compact line
#   --arg r   pass the reason as a jq variable, so quotes, backslashes or
#             newlines inside it are escaped correctly and cannot break the
#             JSON

# deny <reason>
#   Block the pending tool call. Claude Code does not run the tool and shows
#   <reason> to the model, so a good reason says what to do instead.
deny() {  # deny "<reason>"
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
# ask <reason>
#   Do not block outright. Claude Code asks the human to approve the tool call
#   and shows <reason>. Used for actions that are usually wrong but sometimes
#   legitimate, like editing hook config or skipping a test.
ask() {   # ask "<reason>"
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
# allow
#   Exit silently with status 0. No output means "this hook has no objection".
#   It does NOT force approval: Claude Code's normal permission rules and any
#   other hooks still decide whether the tool runs.
allow() { exit 0; }

# git helpers

# current_branch
#   Print the branch checked out in $CWD, or "" when it cannot be determined.
#   Three attempts, in order:
#     1. git symbolic-ref --short -q HEAD
#          The normal case; prints a name such as "feat". It fails quietly on
#          a detached HEAD.
#     2. git rev-parse --abbrev-ref HEAD
#          Prints "HEAD" on a detached HEAD, so callers get a non-empty value.
#     3. echo ""
#          Not a git repository, or git is not installed.
current_branch() { git -C "$CWD" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""; }

# is_main_branch <branch>
#   Return 0 (true) when <branch> is a protected trunk name that an agent must
#   never change, even with a git grant. Return 1 (false) for anything else.
#   Protected names: main, master, trunk, production.
is_main_branch() { case "$1" in main|master|trunk|production) return 0;; *) return 1;; esac; }

# segments <command-string>
#   Print each simple command of a shell command line on its own line, so a
#   guard can check each piece separately. These all become line breaks:
#     ||   &&   ;   |   &            command separators, background
#     $(   (   )   `                 command substitution and subshells
#   Newlines already in the command stay as they are.
#
#   Example:
#       segments 'npm test && x=$(git commit -m ok) | tee log'
#   prints:
#       npm test
#        x=
#       git commit -m ok
#                             <- a blank piece where ")" was
#        tee log
#   Leading spaces are kept; callers trim them. A double separator such as
#   || or && yields a single line break.
#
#   Splitting on substitutions and on a lone & means that commands such as
#   "echo $(git push)" or "sleep 1 & git push" still start a piece with the
#   dangerous command, where the guards look for it.
#
#   The split is deliberately over-eager and ignores quoting:
#     - Separators inside quotes split too: echo "a;b" becomes two pieces.
#     - "2>&1" splits into "2>" and "1".
#   Extra pieces are harmless, because a guard only acts on a piece that
#   contains a dangerous command. Here-docs are not parsed.
#   Writing \n in the replacement to mean a newline is a GNU sed feature.
segments() { printf '%s\n' "$1" | sed -E 's/\|\||&&|\$\(|[;|&()`]/\n/g'; }
