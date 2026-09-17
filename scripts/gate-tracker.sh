#!/usr/bin/env bash
# =============================================================================
# gate-tracker.sh - PostToolUse(Bash) hook: record which verification gates ran
# =============================================================================
#
# PostToolUse(Bash): remember which verification gates actually ran this session.
#
# WHY
#   done-gate.sh will not let an autonomous session finish after source edits
#   unless at least one verification gate ran. This script provides that
#   evidence. After every Bash command it checks whether the command runs a
#   lint, typecheck, build or test tool. Each match is added to the
#   .gates_ran list in the session state file.
#
# WHEN IT RUNS
#   After each Bash tool call. It prints nothing and always exits 0, so it
#   never affects the tool result or the conversation.
#
# HOW A COMMAND IS MATCHED
#   The command is split into pieces by segments() from lib.sh, so
#   "cd web && pnpm test" yields a piece "pnpm test". For each piece, leading
#   wrappers that only launch the real tool are removed, in any combination:
#     VAR=value assignments, sudo, env, time, nice, command, exec,
#     timeout <duration>, npx, bunx, pnpx, pnpm/npm/yarn exec|dlx,
#     uv/poetry/pipenv/hatch run, python -m / python3 -m
#   The gate patterns must then match at the START of the piece. Text that
#   merely mentions a tool, as in git commit -m "run pytest", or a longer
#   name such as "cmake", no longer counts.
#
# GATE PATTERNS (after the wrappers are removed)
#   lint       npm/pnpm/yarn/bun [run] lint*|eslint*, eslint, biome check|lint,
#              ruff check, shellcheck
#   typecheck  npm/pnpm/yarn/bun [run] typecheck*|type-check*|tsc*, tsc, mypy,
#              pyright
#   build      npm/pnpm/yarn/bun [run] build*, next build, vite build,
#              cargo build, go build, make
#   test       npm/pnpm/yarn/bun [run] test*, vitest, jest, pytest,
#              cargo test, go test, playwright test
#   The * means a package script name may continue, as in build:prod or
#   test-unit.
#
# FAILED RUNS
#   A gate counts only when its run did not fail. The hook input's
#   tool_response is checked for any of these:
#     exit_code    a non-zero number
#     is_error     true
#     interrupted  true
#   Any of them means nothing is recorded for that command. When none of
#   these fields are present, the run is recorded.
#
# LIMITATIONS
#   - A gate run through an unlisted wrapper, such as bash -c "pnpm test" or
#     a custom script, is not recognised. That errs on the safe side: the
#     done-gate asks for verification instead of wrongly accepting it.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# The Bash command that just ran. Nothing to record without one.
CMD="$(jget '.tool_input.command')"; [ -z "$CMD" ] && exit 0

# Ignore commands that failed or were interrupted (see FAILED RUNS above).
# jq prints "true" or "false". The type check keeps a missing or non-object
# tool_response from counting as a failure. "// 0" treats a missing
# exit_code as success.
FAILED="$(printf '%s' "$INPUT" | jq -r '.tool_response | if type == "object" then ((.exit_code // 0) != 0) or (.is_error == true) or (.interrupted == true) else false end' 2>/dev/null)"
[ "$FAILED" = "true" ] && exit 0

# $g collects the names of matched gates as a space-separated list.
g=""

# Examine each piece of the command. Process substitution keeps the loop in
# this shell, so changes to $g survive after the loop.
while IFS= read -r seg; do
  # Strip leading whitespace, then any run of launcher wrappers (see header).
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(sudo|env|time|nice|command|exec)[[:space:]]+|timeout[[:space:]]+[0-9.]+[smhd]?[[:space:]]+|(npx|bunx|pnpx)[[:space:]]+|(pnpm|npm|yarn)[[:space:]]+(exec|dlx)[[:space:]]+|(uv|poetry|pipenv|hatch)[[:space:]]+run[[:space:]]+|python3?[[:space:]]+-m[[:space:]]+)*//')"
  [ -z "$seg" ] && continue
  # One anchored grep per gate. `grep -Eq` exits 0 on a match without
  # printing, and the `&&` then appends that gate name to $g.
  printf '%s' "$seg" | grep -Eq '^((pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(lint|eslint)|eslint([[:space:]]|$)|biome[[:space:]]+(check|lint)|ruff[[:space:]]+check|shellcheck([[:space:]]|$))' && g="$g lint"
  printf '%s' "$seg" | grep -Eq '^((pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(typecheck|type-check|tsc)|(tsc|mypy|pyright)([[:space:]]|$))' && g="$g typecheck"
  printf '%s' "$seg" | grep -Eq '^((pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?build|(next|vite|cargo|go)[[:space:]]+build([[:space:]]|$)|make([[:space:]]|$))' && g="$g build"
  printf '%s' "$seg" | grep -Eq '^((pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test|(vitest|jest|pytest)([[:space:]]|$)|(cargo|go|playwright)[[:space:]]+test([[:space:]]|$))' && g="$g test"
done < <(segments "$CMD")

# Not a gate command: leave the state file alone.
[ -z "$g" ] && exit 0

# Make sure the state file exists before updating it.
state_init

# Add each matched gate to .gates_ran. `unique` sorts the array and drops
# duplicates, so running tests ten times still records "test" once.
# $g is left unquoted on purpose so the shell splits it into separate words.
for x in $g; do t="$(mktemp)"; jq --arg x "$x" '.gates_ran = ((.gates_ran + [$x]) | unique)' "$STATE_FILE" > "$t" && mv "$t" "$STATE_FILE"; done
exit 0
