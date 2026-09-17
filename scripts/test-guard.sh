#!/usr/bin/env bash
# =============================================================================
# test-guard.sh - PreToolUse(Edit|Write|MultiEdit|Bash) hook: no fake green
# =============================================================================
#
# PreToolUse(Edit|Write|MultiEdit|Bash): green by deleting or skipping tests is fake green.
#
# WHY
#   A failing test can be "fixed" by skipping it, focusing another test so it
#   never runs, or deleting the file. The suite then passes without anything
#   being fixed. This hook catches those moves and asks the human to approve.
#   It uses `ask`, not `deny`, because sometimes skipping really is right.
#
# BYPASS
#   /gobind:test-allow, which runs `state.sh <session> test-allow`, sets
#   .test_grant=true. The hook then allows everything for the session.
#
# WHAT IS CHECKED
#   Edit / MultiEdit / Write on a test file that ADDS a skip or focus marker
#     compared with the text it replaces                        -> ask
#   Bash commands that rm, unlink, trash or git rm a test file
#     or a test directory                                       -> ask
#   Everything else                                             -> no objection
#
# HOW "ADDS" IS DECIDED
#   Every marker match is collected from the old text and from the new text,
#   with whitespace removed, and sorted. `comm -13` then prints the markers
#   that occur more often in the new text. Repeated lines are paired up, so
#   going from one it.skip( to two counts as adding one. The old text is:
#     Edit       .tool_input.old_string
#     MultiEdit  every .tool_input.edits[].old_string
#     Write      the file currently on disk ("" for a new file)
#   Editing near an existing skip therefore no longer asks, but turning
#   it.skip( into it.only( does.
#
# LIMITATIONS
#   - Other ways to remove tests are not checked, such as mv, find -delete,
#     or emptying a file with a redirect.
#   - Commands are split by segments() from lib.sh, which ignores quoting.
#     A command like: echo "rm tests/x" therefore also asks.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Turn off globbing: command pieces are split into words below, and a * in
# them must stay literal instead of expanding against the hook's cwd.
set -f

# Session-wide bypass granted by the user.
[ "$(state_get '.test_grant')" = "true" ] && allow

# TESTPATH: does a path look like a test file? Alternatives:
#   \.(test|spec)\.[cm]?[jt]sx?$      a.test.ts, a.spec.jsx, a.test.mjs, ...
#   (^|/)(__tests__|tests?|spec|e2e)/  a file inside __tests__/, test/,
#                                      tests/, spec/ or e2e/
#   _test\.(go|py)$                    Go and Python foo_test.go, foo_test.py
#   (^|/)test_[^/]*\.py$               pytest-style test_foo.py
TESTPATH='(\.(test|spec)\.[cm]?[jt]sx?$|(^|/)(__tests__|tests?|spec|e2e)/|_test\.(go|py)$|(^|/)test_[^/]*\.py$)'

# TESTDIR: a word that names a whole test directory, with or without a
# trailing slash, such as "tests", "./e2e/" or "src/__tests__". Only used for
# deletion commands, where removing the directory removes every test in it.
TESTDIR='(^|/)(__tests__|tests?|spec|e2e)/?$'

# SKIP: markers that stop tests from running. Alternatives:
#   it|test|describe .skip( or .todo(      Jest, Vitest, Mocha: skipped
#   xit( xtest( xdescribe(                 Jasmine/Jest: skipped
#   fit( fdescribe(                        focused; every other test is skipped
#   it|test|describe .only(                focused; every other test is skipped
#   @pytest.mark.skip  (also skipif)       pytest
#   @unittest.skip                         Python unittest
#   t.Skip(                                Go
#   #[ignore]                              Rust
# \b and \s are GNU grep extensions to POSIX ERE.
SKIP='(\b(it|test|describe)\.(skip|todo)\s*\(|\b(xit|xtest|xdescribe|fit|fdescribe)\s*\(|\b(it|test|describe)\.only\s*\(|@pytest\.mark\.skip|@unittest\.skip|t\.Skip\(|#\[ignore\])'

# markers
#   Read text on stdin and print each SKIP marker found, one per line, with
#   whitespace removed (so "it.skip (" and "it.skip(" compare equal), sorted
#   in the C locale as `comm` requires.
markers() { grep -oE "$SKIP" | sed 's/[[:space:]]//g' | LC_ALL=C sort; }

case "$TOOL_NAME" in
  # File editing tools.
  Edit|MultiEdit|Write)
    # Edits outside test files are not this hook's concern.
    FP="$(jget '.tool_input.file_path')"
    printf '%s' "$FP" | grep -Eq "$TESTPATH" || allow
    # Collect all new text the tool would write, whichever tool it is:
    #   Edit       .tool_input.new_string
    #   Write      .tool_input.content
    #   MultiEdit  .tool_input.edits[].new_string
    # Missing fields are dropped with select(. != null), and the rest are
    # joined with newlines.
    NEW="$(printf '%s' "$INPUT" | jq -r '[.tool_input.new_string?, .tool_input.content?, (.tool_input.edits[]?.new_string?)] | map(select(. != null)) | join("\n")' 2>/dev/null)"
    # Collect the text being replaced: the current file for Write, or the
    # old_string values for Edit and MultiEdit.
    if [ "$TOOL_NAME" = "Write" ]; then
      OLD="$(cat -- "$FP" 2>/dev/null)"
    else
      OLD="$(printf '%s' "$INPUT" | jq -r '[.tool_input.old_string?, (.tool_input.edits[]?.old_string?)] | map(select(. != null)) | join("\n")' 2>/dev/null)"
    fi
    # Markers present more often in the new text than in the old text.
    ADDED="$(LC_ALL=C comm -13 <(printf '%s\n' "$OLD" | markers) <(printf '%s\n' "$NEW" | markers))"
    # Any added skip or focus marker needs human approval. The markers are
    # listed in the message, joined with spaces.
    [ -n "$ADDED" ] && ask "test-guard: that edit skips or focuses a test in $FP ($(printf '%s' "$ADDED" | tr '\n' ' ')). Gobind's rule: fix, never silence. If a test must be skipped, ask him or use /gobind:test-allow."
    allow;;
  # Shell commands.
  Bash)
    CMD="$(jget '.tool_input.command')"; [ -z "$CMD" ] && allow
    # Check each simple command separately. Process substitution keeps the
    # loop in this shell, so `exit` inside ask ends the hook.
    while IFS= read -r seg; do
      # Only pieces containing a deletion command as a whole word matter:
      # rm, unlink, trash, trash-put, or git rm.
      printf '%s' "$seg" | grep -Eq '(^|[[:space:]])(rm|unlink|trash|trash-put|git[[:space:]]+rm)([[:space:]]|$)' || continue
      # Check every word, with quotes removed, against the test file and
      # test directory patterns. Matching word by word means the test file
      # no longer has to be the last thing in the command.
      for w in $(printf '%s' "$seg" | tr -d "\"'"); do
        printf '%s' "$w" | grep -Eq "$TESTPATH|$TESTDIR" && ask "test-guard: that deletes a test file. Deleting tests is not fixing them. Confirm with Gobind."
      done
    done < <(segments "$CMD")
    allow;;
esac
# Any other tool: no objection.
allow
