#!/usr/bin/env bash
# =============================================================================
# tests/run.sh - end-to-end tests for every hook script
# =============================================================================
#
# Feeds realistic hook JSON to every script and checks the decision. Run: bash tests/run.sh
#
# HOW IT WORKS
#   1. Builds a throwaway project in a temp directory: docs/status.md, src/,
#      and a git repo on "main" with one empty commit.
#   2. Points CLAUDE_PROJECT_DIR at it, so all state files are written there
#      and never into the real repository.
#   3. For each case, builds the JSON Claude Code would send, pipes it into a
#      hook script, turns the hook's output into a one-word decision, and
#      compares it with the expected one.
#   4. Prints a FAIL line for each mismatch and a pass/fail summary at the end.
#
# DECISION WORDS
#   allow  the hook printed nothing, or JSON without a decision
#   deny   hookSpecificOutput.permissionDecision was "deny"
#   ask    hookSpecificOutput.permissionDecision was "ask"
#   block  top-level "decision" was "block" (the Stop hook)
#
# REQUIREMENTS
#   bash, jq, git, timeout, cksum, python3 (to open a listening socket), and
#   ss, which server-guard.sh uses to find the socket.
#
# EXIT STATUS
#   0 when every check passed, 1 otherwise, so the script works in CI.
#
# NOTES
#   - Most cases share one session id, and state carries over between
#     sections. Sections that change the mode or the grant reset it afterwards.
#     The gate-tracker matching cases use their own session ids so they cannot
#     affect the done-gate section.
#   - There is no cleanup trap. If the run is interrupted, the temp directory
#     is left behind.
# =============================================================================

# Error on unset variables. `set -e` is not used; failures are counted instead.
set -u

# Repository root, found from this script's own location, whatever the
# caller's working directory is.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Directory holding the scripts under test.
S="$ROOT/scripts"

# Temporary project directory. Exporting CLAUDE_PROJECT_DIR makes every hook
# and state.sh keep its state in $TMP/.claude/gobind.
TMP="$(mktemp -d)"; export CLAUDE_PROJECT_DIR="$TMP"
# A state doc (used by docs-nudge and done-gate) and a source directory.
mkdir -p "$TMP/docs" "$TMP/src"; echo "# status" > "$TMP/docs/status.md"
# A git repo on "main" with one empty commit, so current_branch works and
# checkouts succeed. The inline -c options supply an identity for the commit
# without touching global git config.
git -C "$TMP" init -q; git -C "$TMP" checkout -q -b main 2>/dev/null; git -C "$TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

# Counters for the summary.
pass=0; fail=0
# Session id unique to this run ($$ is the shell's PID).
SID="test-$$"

# j <jq-program>
#   Build compact JSON with jq. $sid and $cwd are available inside the
#   program. Callers write them as \$sid and \$cwd inside double quotes, so
#   the shell leaves them for jq to fill in.
j() { jq -cn --arg sid "$SID" --arg cwd "$TMP" "$1"; }

# decision
#   Read a hook's stdout and print one decision word.
#     empty output             -> allow
#     permissionDecision field -> that value (deny / ask)
#     else top-level decision  -> that value (block)
#     neither, or not JSON     -> allow
decision() { local o; o="$(cat)"; if [ -z "$o" ]; then echo allow; else printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision // .decision // "allow"' 2>/dev/null || echo allow; fi; }

# check <name> <expected> <actual>
#   Count a pass, or count a fail and print what differed.
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected $2, got $3)"; fi
}

# bash_in <command>
#   JSON for a PreToolUse event of the Bash tool running <command>.
#   <command> is pasted into a jq string literal, so any double quotes in it
#   must be written as \" by the caller.
bash_in() { j "{session_id:\$sid,cwd:\$cwd,hook_event_name:\"PreToolUse\",tool_name:\"Bash\",tool_input:{command:\"$1\"}}"; }

# file_in <tool> <file_path> <text>
#   JSON for a PreToolUse event of a file tool. <text> is placed in both
#   new_string (Edit) and content (Write), so one helper serves both tools.
file_in() { j "{session_id:\$sid,cwd:\$cwd,hook_event_name:\"PreToolUse\",tool_name:\"$1\",tool_input:{file_path:\"$2\",new_string:\"$3\",content:\"$3\"}}"; }

# edit_in <file_path> <old_string> <new_string>
#   JSON for an Edit that replaces <old_string> with <new_string>.
edit_in() { j "{session_id:\$sid,cwd:\$cwd,hook_event_name:\"PreToolUse\",tool_name:\"Edit\",tool_input:{file_path:\"$1\",old_string:\"$2\",new_string:\"$3\"}}"; }

# write_in <file_path> <content>
#   JSON for a Write of <content> to <file_path>. A \n inside <content> is a
#   newline once jq parses the string.
write_in() { j "{session_id:\$sid,cwd:\$cwd,hook_event_name:\"PreToolUse\",tool_name:\"Write\",tool_input:{file_path:\"$1\",content:\"$2\"}}"; }

# run <script>
#   Run a hook script with the JSON on stdin and print its decision word.
run() { "$S/$1" | decision; }

# ---- git-guard ----------------------------------------------------------------
echo "== git-guard"
# Without a grant, read-only git must pass. This includes reads that look
# like other commands: a config key lookup, branch listing with a pattern or
# filter, and a path that merely ends in "git". The compound case checks that
# segments() finds the git part.
for c in "git status" "git log --oneline -5" "git diff HEAD~1" "git show abc" "git branch" "git branch -a" "git stash list" "git remote -v" "git config --get user.name" "git tag -l" "cd /tmp && git status && ls" "git config user.name" "git config --list" "git config get user.name" "git config --global --get-regexp alias" "git branch --list 'feat*'" "git branch --contains HEAD" "ls tools/git"; do
  check "allow: $c" allow "$(bash_in "$c" | run git-guard.sh)"; done
# Without a grant, every mutation must be denied. This covers mutations
# hidden after &&, gh write commands, and global options before the
# subcommand (git -C dir push).
for c in "git commit -m x" "git push" "git pull" "git add ." "git add -f foo.nds" "git checkout -b feat" "git switch main" "git reset --hard" "git stash" "git merge feat" "git rebase main" "git fetch" "git branch -D feat" "git branch feat2" "git remote add up x" "git clean -fd" "npm test && git commit -m ok" "gh pr create -t x" "gh pr merge 1" "git -C /tmp/x push origin main"; do
  check "deny: $c" deny "$(bash_in "$c" | run git-guard.sh)"; done
# Ways of hiding a mutation that used to slip through: a full path, env or
# assignment prefixes, command substitution, background &, shell keywords,
# braces and bash -c. Also branch creation with two arguments or -v, and
# config writes in both old and new syntax.
for c in "/usr/bin/git commit -m x" "env git commit -m x" "env FOO=1 git push" "GIT_TRACE2=1 git push" "sudo /usr/bin/git push" "echo \$(git push)" "x=\$(git commit -m y)" "sleep 1 & git push" "if git push; then :; fi" "{ git push; }" "bash -c 'git push'" "/usr/bin/gh pr merge 1" "git branch feat2 main" "git branch -v feat3" "git config user.name x" "git config --global core.editor vim" "git config --unset user.name" "git config set user.name x"; do
  check "deny: $c" deny "$(bash_in "$c" | run git-guard.sh)"; done
# A global option with its value missing must not hang the hook. The exit
# status of the pipeline is timeout's: 124 when the hook had to be killed.
for c in "git -C" "git -c"; do
  bash_in "$c" | timeout 5 "$S/git-guard.sh" >/dev/null; check "terminates: $c" 0 "$?"; done
# Grant the "feat" branch and check it out.
"$S/state.sh" "$SID" git-allow feat >/dev/null
git -C "$TMP" checkout -q -b feat 2>/dev/null
# On the granted branch, normal feature-branch work passes. A PR title that
# contains "merge" is not mistaken for a merge.
for c in "git add ." "git commit -m x" "git push -u origin feat" "git fetch" "gh pr create -t merge-fix"; do check "granted allow: $c" allow "$(bash_in "$c" | run git-guard.sh)"; done
# Even with the grant, main is off limits, force pushes are blocked, and
# gh merges are denied.
for c in "git push origin main" "git push --force" "git merge main" "git checkout main" "git switch main" "gh pr merge 1"; do check "granted deny: $c" deny "$(bash_in "$c" | run git-guard.sh)"; done
# Move to main with the grant still active: committing there is denied.
git -C "$TMP" checkout -q main 2>/dev/null
check "granted but on main: commit" deny "$(bash_in 'git commit -m x' | run git-guard.sh)"
# Revoke the grant; commits are denied again.
"$S/state.sh" "$SID" git-lock >/dev/null
check "relocked: commit" deny "$(bash_in 'git commit -m x' | run git-guard.sh)"

# ---- secrets-guard ------------------------------------------------------------
echo "== secrets-guard"
# File tools: real secret files are denied; templates and look-alikes pass.
check "Read .env" deny "$(file_in Read /p/.env '' | run secrets-guard.sh)"
check "Read .env.local" deny "$(file_in Read /p/.env.local '' | run secrets-guard.sh)"
check "Read .env.example" allow "$(file_in Read /p/.env.example '' | run secrets-guard.sh)"
check "Edit id_rsa" deny "$(file_in Edit /home/u/.ssh/id_rsa '' | run secrets-guard.sh)"
check "Read src/env.ts" allow "$(file_in Read /p/src/env.ts '' | run secrets-guard.sh)"
# Bash: reading secret files, dumping the environment, or echoing secret
# variables is denied; harmless variants pass.
check "cat .env" deny "$(bash_in 'cat .env' | run secrets-guard.sh)"
check "grep key .env.production" deny "$(bash_in 'grep KEY .env.production' | run secrets-guard.sh)"
check "printenv" deny "$(bash_in 'printenv' | run secrets-guard.sh)"
check "printenv HOME" allow "$(bash_in 'printenv HOME' | run secrets-guard.sh)"
check "ls -la" allow "$(bash_in 'ls -la' | run secrets-guard.sh)"
check "echo \$API_KEY" deny "$(bash_in 'echo $STRIPE_API_KEY' | run secrets-guard.sh)"
check "cat .env.example" allow "$(bash_in 'cat .env.example' | run secrets-guard.sh)"
# Bash now uses the same secret file list as the file tools, checks every
# word, and sees reads inside $( ), after a redirect, and inside quotes.
for c in "cat server.key" "cat ~/.npmrc" "cat .env .env.example" "cat .env.example .env" 'echo $(cat .env)' "cat<.env" "grep x < .env" 'cat \"$HOME/.aws/credentials\"'; do
  check "deny: $c" deny "$(bash_in "$c" | run secrets-guard.sh)"; done
for c in "cat package.json" "grep -r TODO src" "source .venv/bin/activate"; do
  check "allow: $c" allow "$(bash_in "$c" | run secrets-guard.sh)"; done

# ---- server-guard -------------------------------------------------------------
echo "== server-guard"
# Blanket kills are denied without looking at any ports.
check "pkill node" deny "$(bash_in 'pkill node' | run server-guard.sh)"
check "pkill -f next" deny "$(bash_in 'pkill -f next' | run server-guard.sh)"
check "killall node" deny "$(bash_in 'killall node' | run server-guard.sh)"
check "fuser -k 3000/tcp" deny "$(bash_in 'fuser -k 3000/tcp' | run server-guard.sh)"
check "ls" allow "$(bash_in 'ls' | run server-guard.sh)"
# A PID that almost certainly does not exist owns no port, so kill passes.
check "kill 999999 (no port)" allow "$(bash_in 'kill 999999' | run server-guard.sh)"
# Simulate a running dev server: a Python process listening on 127.0.0.1:39877
# for 8 seconds, in the background. $! is its PID. The short sleep gives the
# socket time to start listening before the checks run.
python3 -c "import socket,time;s=socket.socket();s.bind(('127.0.0.1',39877));s.listen();time.sleep(8)" & LPID=$!; sleep 0.5
check "kill pid owning a port" deny "$(bash_in "kill $LPID" | run server-guard.sh)"
check "pnpm dev on busy port" deny "$(bash_in 'pnpm dev --port 39877' | run server-guard.sh)"
check "pnpm dev on free port" allow "$(bash_in 'pnpm dev --port 39878' | run server-guard.sh)"
# Stop the fake server and reap it so no background job outlives the test.
kill $LPID 2>/dev/null; wait $LPID 2>/dev/null

# ---- question-gate ------------------------------------------------------------
echo "== question-gate"
# QIN is an ordinary question. QSC is tagged as the named stop-condition.
QIN="$(j '{session_id:$sid,cwd:$cwd,tool_name:"AskUserQuestion",tool_input:{questions:[{question:"Which colour?",header:"Colour"}]}}')"
QSC="$(j '{session_id:$sid,cwd:$cwd,tool_name:"AskUserQuestion",tool_input:{questions:[{question:"[stop-condition] this changes gameplay, ok?",header:"Gameplay"}]}}')"
# Collab mode: questions are fine.
check "collab: question allowed" allow "$(printf '%s' "$QIN" | run question-gate.sh)"
# Autonomous mode: ordinary questions are denied; tagged ones pass.
"$S/state.sh" "$SID" set-mode autonomous "only if gameplay is affected" >/dev/null
check "autonomous: question denied" deny "$(printf '%s' "$QIN" | run question-gate.sh)"
check "autonomous: stop-condition allowed" allow "$(printf '%s' "$QSC" | run question-gate.sh)"
# Restore collab for the following sections.
"$S/state.sh" "$SID" set-mode collab >/dev/null

# ---- prompt-reminder ----------------------------------------------------------
echo "== prompt-reminder (auto mode switch)"
# PIN <message>: JSON for a UserPromptSubmit event carrying <message>.
PIN() { j "{session_id:\$sid,cwd:\$cwd,hook_event_name:\"UserPromptSubmit\",prompt:\"$1\"}"; }
# A neutral message should produce the collab reminder. The hook prints one
# line of JSON, so grep -c counts 1 when the reminder is present and 0 when
# it is missing.
out="$(PIN "fix the bug pls" | "$S/prompt-reminder.sh")"; check "collab context present" 1 "$(printf '%s' "$out" | grep -c 'mode: collab')"
# A "going to sleep" message switches to autonomous and captures the
# "only ask if gameplay is affected" clause as the stop-condition.
out="$(PIN "okay im going to sleep, dont ask me questions, only ask if gameplay is affected" | "$S/prompt-reminder.sh")"
check "autonomous detected" autonomous "$("$S/state.sh" "$SID" show | sed -n 's/^mode: //p')"
check "stop-condition captured" 1 "$("$S/state.sh" "$SID" show | grep -c 'gameplay')"
# "im back" switches back to collab.
out="$(PIN "im back, normal mode" | "$S/prompt-reminder.sh")"
check "back to collab" collab "$("$S/state.sh" "$SID" show | sed -n 's/^mode: //p')"

# ---- config-guard / test-guard ------------------------------------------------
echo "== config-guard / test-guard"
# Editing settings asks; ordinary source edits pass.
check "edit settings.json asks" ask "$(file_in Edit "$TMP/.claude/settings.json" '' | run config-guard.sh)"
check "edit src allowed" allow "$(file_in Edit "$TMP/src/a.ts" '' | run config-guard.sh)"
# Adding it.skip to a test file asks; a normal test edit passes; deleting a
# spec file asks. The \" sequences are quotes inside the JSON string.
check "skip test asks" ask "$(file_in Edit "$TMP/src/a.test.ts" 'it.skip(\"x\", () => {})' | run test-guard.sh)"
check "normal test edit allowed" allow "$(file_in Edit "$TMP/src/a.test.ts" 'it(\"x\", () => {})' | run test-guard.sh)"
check "rm test asks" ask "$(bash_in 'rm src/a.spec.ts' | run test-guard.sh)"
# Only ADDED markers ask. Editing a test that is already skipped passes;
# turning a skip into a focus asks.
check "edit keeping an existing skip allowed" allow "$(edit_in "$TMP/src/a.test.ts" 'it.skip(\"x\", () => {})' 'it.skip(\"x\", () => { expect(1) })' | run test-guard.sh)"
check "edit turning skip into only asks" ask "$(edit_in "$TMP/src/a.test.ts" 'it.skip(\"x\", () => {})' 'it.only(\"x\", () => {})' | run test-guard.sh)"
# For Write, the old text is the file on disk. Keeping its one skip passes;
# adding a second skip asks.
printf 'it.skip("x", () => {})\n' > "$TMP/src/b.test.ts"
check "rewrite keeping existing skip allowed" allow "$(write_in "$TMP/src/b.test.ts" 'it.skip(\"x\", () => {})\nit(\"y\", () => {})' | run test-guard.sh)"
check "write adding a second skip asks" ask "$(write_in "$TMP/src/b.test.ts" 'it.skip(\"x\", () => {})\nit.skip(\"y\", () => {})' | run test-guard.sh)"
# Deleting tests is caught wherever the path sits in the command, and for
# whole test directories. Deleting ordinary files or listing tests passes.
for c in "rm tests/a.py" "rm src/a.test.ts && ls" "git rm -r tests" "rm -rf e2e/" "cd src && rm -f a.spec.ts b.ts"; do
  check "ask: $c" ask "$(bash_in "$c" | run test-guard.sh)"; done
for c in "rm src/a.ts" "ls tests/" "rm -rf node_modules"; do
  check "allow: $c" allow "$(bash_in "$c" | run test-guard.sh)"; done

# ---- gate-tracker matching ----------------------------------------------------
echo "== gate-tracker (matching)"
# gates_for <command> [tool_response-json]
#   Feed one PostToolUse event to gate-tracker.sh and print the recorded gates
#   as state.sh shows them, such as "lint, typecheck" or "(none)". Each
#   distinct input gets its own session id, derived from a checksum, so
#   cases cannot see each other's state.
gates_for() {
  local s; s="gates-$$-$(printf '%s %s' "$1" "${2:-}" | cksum | cut -d' ' -f1)"
  jq -cn --arg sid "$s" --arg cwd "$TMP" --arg c "$1" --argjson r "${2:-null}" '{session_id:$sid,cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},tool_response:$r}' | "$S/gate-tracker.sh"
  "$S/state.sh" "$s" show | sed -n 's/^gates run: //p'
}
# Real gate commands, including ones behind launchers and prefixes.
check "gates: pnpm lint && pnpm typecheck" "lint, typecheck" "$(gates_for 'pnpm lint && pnpm typecheck')"
check "gates: npx tsc --noEmit" typecheck "$(gates_for 'npx tsc --noEmit')"
check "gates: python -m pytest -q" test "$(gates_for 'python -m pytest -q')"
check "gates: uv run pytest" test "$(gates_for 'uv run pytest')"
check "gates: cd web && pnpm test" test "$(gates_for 'cd web && pnpm test')"
check "gates: FOO=1 timeout 300 cargo test" test "$(gates_for 'FOO=1 timeout 300 cargo test')"
check "gates: npm run build:prod" build "$(gates_for 'npm run build:prod')"
check "gates: make" build "$(gates_for 'make')"
check "gates: ruff check ." lint "$(gates_for 'ruff check .')"
# Commands that only mention a tool, or contain one inside a longer word,
# must not count.
check "gates: cmake .." "(none)" "$(gates_for 'cmake ..')"
check "gates: ruff format ." "(none)" "$(gates_for 'ruff format .')"
check "gates: commit message mentioning tools" "(none)" "$(gates_for "git commit -m 'run pytest and jest'")"
check "gates: echo vitest" "(none)" "$(gates_for 'echo vitest')"
# Failed or interrupted runs are not recorded; a successful one is.
check "gates: failed pnpm test" "(none)" "$(gates_for 'pnpm test' '{"exit_code":1}')"
check "gates: errored pnpm test" "(none)" "$(gates_for 'pnpm test' '{"is_error":true}')"
check "gates: interrupted pnpm test" "(none)" "$(gates_for 'pnpm test' '{"interrupted":true}')"
check "gates: passing pnpm test" test "$(gates_for 'pnpm test' '{"exit_code":0,"stdout":"ok"}')"

# ---- docs-nudge / gate-tracker / done-gate ------------------------------------
echo "== docs-nudge / gate-tracker / done-gate"
# Autonomous mode, so done-gate is active. set-mode also resets stop_blocks.
"$S/state.sh" "$SID" set-mode autonomous >/dev/null
# Seven source edits produce no nudge...
for i in 1 2 3 4 5 6 7; do file_in Edit "$TMP/src/f$i.ts" '' | "$S/docs-nudge.sh" >/dev/null; done
# ...and the eighth one does.
out="$(file_in Edit "$TMP/src/f8.ts" '' | "$S/docs-nudge.sh")"; check "nudge at 8" 1 "$(printf '%s' "$out" | grep -c 'source files edited')"
# A Stop event. stop_hook_active=false means the agent is not already
# continuing because of a Stop hook.
STOPIN="$(j '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop",stop_hook_active:false}')"
# Source changed, no gate ran, and the docs are stale: done-gate blocks.
check "done-gate blocks (no gates, stale docs)" block "$(printf '%s' "$STOPIN" | run done-gate.sh)"
# Run lint and typecheck (recorded by gate-tracker) and touch the state doc
# (which resets the since-docs counter).
bash_in 'pnpm lint && pnpm typecheck' | "$S/gate-tracker.sh"
file_in Edit "$TMP/docs/status.md" '' | "$S/docs-nudge.sh" >/dev/null
# Both reasons are resolved: done-gate lets the session stop.
check "done-gate passes after gates + docs" allow "$(printf '%s' "$STOPIN" | run done-gate.sh)"
# In collab mode done-gate never blocks.
"$S/state.sh" "$SID" set-mode collab >/dev/null
check "done-gate silent in collab" allow "$(printf '%s' "$STOPIN" | run done-gate.sh)"

# ---- session-index ------------------------------------------------------------
echo "== session-index"
# Simulate a SessionStart after compaction.
out="$(j '{session_id:$sid,cwd:$cwd,hook_event_name:"SessionStart",source:"compact"}' | "$S/session-index.sh")"
# The index must include the rules line, the compaction note, and stay
# within 20 lines.
check "index has rules" 1 "$(printf '%s' "$out" | grep -c 'rules: 1)')"
check "index notes compaction" 1 "$(printf '%s' "$out" | grep -c 'compacted')"
check "index ≤ 20 lines" 1 "$( [ "$(printf '%s\n' "$out" | wc -l)" -le 20 ] && echo 1 || echo 0)"

# ---- summary ------------------------------------------------------------------
# Remove the temporary project.
rm -rf "$TMP"
# Print totals. The final test sets the exit status: 0 only when nothing failed.
echo; echo "passed: $pass  failed: $fail"; [ "$fail" -eq 0 ]
