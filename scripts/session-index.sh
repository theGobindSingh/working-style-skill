#!/usr/bin/env bash
# =============================================================================
# session-index.sh - SessionStart hook: print a short orientation index
# =============================================================================
#
# SessionStart(startup|resume|clear|compact): a ≤20-line index so a fresh or compacted
# context knows the mode, the state of the repo, and the five rules that matter most.
#
# WHEN IT RUNS
#   hooks/hooks.json registers it for SessionStart with the matcher
#   startup|resume|clear|compact. That covers a new session, a resumed one,
#   one reset with /clear, and one whose history was just compacted.
#
# WHAT IT DOES
#   1. Deletes state files of sessions untouched for more than 7 days.
#   2. Prints a small index to stdout. For SessionStart hooks, Claude Code adds
#      stdout to the model's context, so the agent starts each session knowing:
#        - the time, why the session started, the mode and any stop-condition
#        - the git branch, how many files are uncommitted, and the git grant
#        - the first 8 lines of docs/status.md or docs/STATE.md
#        - whether docs/status.md holds a "## Handoff" section to read first
#        - the five core rules, the mode-switch phrases, and slash commands
#        - after a compaction, a reminder to reload context from the docs
#
# CONSTRAINTS
#   - The output must stay at 20 lines or fewer; tests/run.sh checks this.
#   - It always exits 0 and hides stderr, so a broken repo or a missing file
#     can never stop a session from starting.
#
# INPUT FIELDS USED
#   .source      startup | resume | clear | compact
#   .session_id  and .cwd, read by lib.sh
# =============================================================================

# Load the shared helpers. This also reads the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Why the session started. Empty when missing; it is shown as "startup" then.
SRC="$(jget '.source')"

# Housekeeping: delete session-*.json files last modified more than 7 days ago.
#   -maxdepth 1   only look directly inside .claude/gobind/
#   -mtime +7     modification time older than 7 whole days
# Errors are ignored, for example when the directory does not exist yet.
# prune state files from sessions older than 7 days so .claude/gobind never piles up
find "$STATE_DIR" -maxdepth 1 -name 'session-*.json' -mtime +7 -delete 2>/dev/null || true

# Read the three state values shown in the index. state_get creates the
# state file with defaults if this is a new session.
MODE="$(state_get '.mode')"; SC="$(state_get '.stop_condition')"; GRANT="$(state_get '.git_grant')"

# Everything inside { ... } writes to stdout, which becomes model context.
# The trailing 2>/dev/null silences errors from every command in the group.
{
  # Line 1: timestamp, session source, mode, and the stop-condition if any.
  # The $( ... ) at the end prints " | stop-condition: ..." only when set.
  echo "[gobind] $(now_iso) | session ${SRC:-startup} | mode: ${MODE:-collab}$( [ -n "$SC" ] && printf ' | stop-condition: %s' "$SC")"
  # Line 2, only inside a git work tree: branch, count of changed files, and
  # git permissions.
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # `git status --porcelain` prints one line per changed or untracked file.
    # wc -l counts them; tr strips the padding some wc versions add.
    b="$(current_branch)"; n="$(git -C "$CWD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    echo "[gobind] branch: $b | uncommitted files: $n | git: $( [ -n "$GRANT" ] && echo "granted on '$GRANT'" || echo "only when asked (no commit/pull/push on your own)")"
  fi
  # Show the head of the project's state doc. docs/status.md is preferred;
  # docs/STATE.md is the fallback. `break` stops after the first one found.
  # Each line is indented by four spaces so it reads as quoted content.
  for f in docs/status.md docs/STATE.md; do
    if [ -f "$CWD/$f" ]; then
      echo "[gobind] $f (head):"; sed -n '1,8p' "$CWD/$f" | sed 's/^/    /'; break
    fi
  done
  # A "## Handoff" heading, matched case-insensitively at the start of a
  # line, means an earlier session left notes. The agent should read them
  # before planning anything.
  if [ -f "$CWD/docs/status.md" ] && grep -qi '^## handoff' "$CWD/docs/status.md"; then
    echo "[gobind] a Handoff section exists in docs/status.md: read it before planning."
  fi
  # The five core rules. They stay on one line to respect the 20-line budget.
  echo "[gobind] rules: 1) no git changes unless he asks  2) questions once, up front; none mid-task in autonomous mode  3) root cause before fix, evidence for every claim  4) smallest diff, reuse before adding, fix lint never silence it  5) verify in the real runtime; recap says VERIFIED / NOT VERIFIED / BLOCKED"
  # Phrases that prompt-reminder.sh recognises, and the available commands.
  echo "[gobind] mode phrases: 'going to sleep' / 'full autonomous' -> autonomous; 'i'm back' / 'normal mode' -> collab. Commands: /gobind:mode /gobind:recap /gobind:handoff /gobind:questions /gobind:rca"
  # After compaction the model has lost detail from earlier in the session.
  # Tell it to reload from the docs and not to repeat answered questions.
  [ "$SRC" = "compact" ] && echo "[gobind] context was compacted: re-read docs/status.md and your last recap before continuing; do not re-ask questions already answered."
} 2>/dev/null
# Always succeed, whatever happened above.
exit 0
