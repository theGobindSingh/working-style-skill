#!/usr/bin/env bash
# =============================================================================
# secrets-guard.sh - PreToolUse(Read|Edit|Write|MultiEdit|NotebookEdit|Bash) hook
# =============================================================================
#
# PreToolUse(Read|Edit|Write|MultiEdit|Bash): never read, edit or print secrets.
#
# WHY
#   Anything the agent reads lands in the conversation transcript, and may be
#   logged or sent to external services. Secrets must never get there. The
#   agent should name the variables it needs, and the user sets them.
#
# SECRET FILES (the SECRET_PATH regex, shared by file tools and Bash)
#   .env and .env.<anything>        dotenv files
#   *.pem, *.key                    certificates and private keys
#   id_rsa, id_ed25519, id_ecdsa    SSH keys, including the .pub halves
#   credentials*.json               e.g. Google OAuth client credentials
#   service-account*.json           GCP service account keys
#   .netrc, .npmrc, .pypirc         files that often hold registry tokens
#   .aws/credentials                AWS keys
#   Template files (.env.example, .env.sample, .env.template, .env.dist,
#   .env.defaults) are always allowed: they hold no real values.
#
# FILE TOOLS (Read, Edit, Write, MultiEdit, NotebookEdit)
#   Denied when the target path is a secret file.
#
# BASH, CHECKED FOR EACH SIMPLE COMMAND
#   1. A reading or copying command (cat, less, head, grep, source, cp,
#      base64, an editor, ...) together with any word that is a secret file.
#      Each word is checked on its own, so a template elsewhere in the same
#      command does not excuse a real secret file.
#   2. A bare environment dump: printenv, env, set, export -p, declare -x.
#      "printenv NAME" for a single variable is allowed.
#   3. echo of a variable whose name contains SECRET, TOKEN, PASSWORD,
#      PASSWD, API_KEY, PRIVATE_KEY or ACCESS_KEY.
#
# LIMITATIONS
#   - Indirect reads are not seen, such as a script or program that opens
#     .env itself, or a recursive grep over a directory.
#   - A search pattern that looks like a secret file name, as in
#     grep api.key src, is treated as a file and denied.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Turn off globbing: command pieces are split into words below, and a * in
# them must stay literal instead of expanding against the hook's cwd.
set -f

# Paths that hold secrets. Each (^|/) anchors a name to a whole path component,
# and $ anchors it to the end of the path.
SECRET_PATH='(^|/)\.env(\.[A-Za-z0-9_-]+)?$|\.pem$|\.key$|(^|/)id_(rsa|ed25519|ecdsa)(\.pub)?$|credentials[^/]*\.json$|(^|/)\.netrc$|(^|/)\.npmrc$|(^|/)\.pypirc$|service-account[^/]*\.json$|(^|/)\.aws/credentials$'

# Committed template versions of .env files. These are safe to read and edit.
EXAMPLE='\.env\.(example|sample|template|dist|defaults)$'

# Commands that read, copy, print or open a file, as whole words. "\." is the
# shell's "." (source) command.
READER='(^|[[:space:]])(cat|less|more|head|tail|bat|sed|awk|grep|rg|source|\.|cp|scp|base64|xxd|od|strings|tee|vim?|nano|code)[[:space:]]'

case "$TOOL_NAME" in
  # ---- file tools -------------------------------------------------------------
  Read|Edit|Write|MultiEdit|NotebookEdit)
    # Most tools use file_path; NotebookEdit uses notebook_path.
    FP="$(jget '.tool_input.file_path')"; [ -z "$FP" ] && FP="$(jget '.tool_input.notebook_path')"
    [ -z "$FP" ] && allow
    # Templates win over the secret patterns, so .env.example is always fine.
    printf '%s' "$FP" | grep -Eq "$EXAMPLE" && allow
    printf '%s' "$FP" | grep -Eq "$SECRET_PATH" && deny "secrets-guard: $FP holds secrets. Gobind's rule: never read, edit or print .env or key files. Tell him which keys you need and he will set them."
    allow;;
  # ---- shell commands ---------------------------------------------------------
  Bash)
    CMD="$(jget '.tool_input.command')"; [ -z "$CMD" ] && allow
    # Check each simple command. segments() also splits at $( and backticks,
    # so "echo $(cat .env)" yields a piece starting with "cat .env".
    # Process substitution keeps the loop in this shell, so `exit` inside
    # deny ends the hook.
    # any segment that reads/prints a secret file, or dumps the environment
    while IFS= read -r seg; do
      # Normalise the piece into plain words:
      #   tr -d        remove double and single quotes
      #   tr '<>='     turn redirections and "=" into spaces, so cat<.env,
      #                grep x < .env and --file=.env expose the file name as
      #                its own word
      words="$(printf '%s' "$seg" | tr -d "\"'" | tr '<>=' '   ')"
      # Check 1: a reading command plus a secret file among the words.
      if printf '%s' "$words" | grep -Eq "$READER"; then
        # $words is unquoted so the shell splits it; globbing is off.
        for w in $words; do
          # A template is fine; keep checking the other words.
          printf '%s' "$w" | grep -Eq "$EXAMPLE" && continue
          printf '%s' "$w" | grep -Eq "$SECRET_PATH" && deny "secrets-guard: that command reads or copies a secrets file. Never print .env or key contents. Name the keys you need instead."
        done
      fi
      # Check 2: an environment dump with no arguments. The anchors on both
      # ends mean "printenv HOME" does not match.
      printf '%s' "$seg" | grep -Eq '^[[:space:]]*(printenv|env|set|export -p|declare -x)[[:space:]]*$' && deny "secrets-guard: dumping the whole environment prints secrets. Query one variable name instead (printenv NAME)."
      # Check 3: echo of $NAME or ${NAME where NAME contains a secret-looking
      # word, such as $STRIPE_API_KEY.
      printf '%s' "$seg" | grep -Eq 'echo[[:space:]]+.*\$\{?[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|ACCESS_KEY)' && deny "secrets-guard: that echoes a secret-looking variable. Check for presence with [ -n \"\$VAR\" ] instead."
    done < <(segments "$CMD")
    allow;;
esac
# Any other tool: no objection.
allow
