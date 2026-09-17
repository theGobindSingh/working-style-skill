#!/usr/bin/env bash
# =============================================================================
# git-guard.sh - PreToolUse(Bash) hook: git belongs to the user
# =============================================================================
#
# PreToolUse(Bash): git is Gobind's. Read-only git passes; mutations are denied unless a
# session grant names the current branch (or "*"). main/master stay locked even with a grant.
#
# GRANTS
#   The grant lives in .git_grant in the session state file:
#     ""         no grant; git is read-only             (/gobind:git-lock)
#     "<branch>" mutations allowed while on <branch>    (/gobind:git-allow)
#     "*"        mutations allowed on any branch that is not protected
#
# FINDING git IN A COMMAND LINE
#   The command is split into pieces by segments() from lib.sh, which also
#   breaks at $( ... ), parentheses, backticks and a lone &. Each piece is
#   then normalised before it is judged:
#     - all quote characters are removed, so bash -c 'git push' and
#       git push origin "main" are read as plain words
#     - leading wrappers are removed, in any combination: sudo, env, command,
#       exec, eval, nohup, time, the shell keywords if/then/else/elif/do/
#       while/until, "!", "{", "bash -c" / "sh -c" / "zsh -c", and variable
#       assignments such as GIT_TRACE2=1
#     - a path in front of git or gh is removed, so /usr/bin/git is git
#
# DECISION RULES FOR EACH git COMMAND IN THE COMMAND LINE
#   1. Read-only subcommands (status, log, diff, show, blame, ...) pass. A few
#      of them have mutating forms, which are denied even with a grant:
#        git remote   add|remove|rm|rename|set-url|prune
#        git config   any write (see config_writes below); reads pass
#        git worktree add|remove|prune|move|lock|unlock
#        git reflog   expire|delete
#   2. Special cases:
#        git branch   listing passes. Delete, move, copy, upstream changes,
#                     or naming a branch outside list mode (which creates
#                     it) are denied, even with a grant.
#        git stash    list/show pass; anything else is denied, even with a grant
#        git tag      bare or -l/--list/-n pass; anything else is denied, even
#                     with a grant
#        git fetch    denied without a grant; allowed with one
#   3. Every other subcommand is treated as mutating: commit, push, pull,
#      merge, rebase, reset, checkout, switch, restore, add, rm, and so on.
#        No grant   -> denied
#        With grant -> denied when any of these hold:
#          a. the current branch is protected (main, master, trunk,
#             production) and the command writes to it
#          b. the arguments name main or master and the command could move
#             or change it: push, merge, rebase, reset, checkout, switch
#          c. a push forces, mirrors, pushes all branches, or deletes
#          d. the grant names a specific branch, the current branch is a
#             different one, and the command writes history
#        Otherwise allowed.
#   4. gh pr/release/issue/repo with the action create, merge, close, delete,
#      edit, reopen, comment, review or ready is denied without a grant. With
#      a grant, the merge and delete actions are still denied.
#
# KNOWN LIMITATIONS
#   - Wrappers with their own options before git are not unwrapped, such as
#     "sudo -u someone git push" or "env -i git push". Neither is
#     "xargs git ..." or a script or alias that runs git internally.
#   - gh global options placed before the subcommand, such as
#     "gh -R owner/repo pr merge 1", are not recognised.
#   - Because quotes are removed and splitting ignores quoting, text inside
#     a quoted argument can occasionally look like a command, as in
#     echo "(git push)". That produces a false denial, never a missed one.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Turn off pathname expansion (globbing) for the rest of this script. Pieces
# of the command are split into words with unquoted expansions below. Without
# this, a * in the command could be expanded against files in the hook's own
# working directory and change what is being judged.
set -f

# Only Bash commands are relevant. The hooks.json matcher already ensures
# this; the check keeps the script safe if it is registered more broadly.
[ "$TOOL_NAME" = "Bash" ] || allow
CMD="$(jget '.tool_input.command')"
[ -z "$CMD" ] && allow

# Quick pre-check: skip everything below unless "git" or "gh" appears as a
# standalone word. The character before must not be a letter, digit, _, . or
# -, and a space or the end of the text must follow. A "/" before is allowed
# so /usr/bin/git is found. This avoids false hits such as "legit" or "digit".
printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_.-])(git|gh)([[:space:]]|$)' || allow

# The session's grant and the branch currently checked out in $CWD.
GRANT="$(state_get '.git_grant')"
BRANCH="$(current_branch)"

# Subcommands that only read. The regex is anchored at both ends, so it must
# match the whole subcommand word.
READ_ONLY='^(status|log|diff|show|blame|shortlog|describe|rev-parse|rev-list|ls-files|ls-tree|cat-file|grep|reflog|remote|config|help|version|worktree|count-objects|check-ignore|name-rev|for-each-ref|whatchanged|range-diff)$'

# deny_git <description>
#   Deny with a message that fits the situation:
#     - without a grant, explain that git is read-only and how to get a grant
#     - with a grant, explain that this command or branch is outside it
#   deny exits, so nothing after a deny_git call runs.
deny_git() {
  local why="$1"
  if [ -z "$GRANT" ]; then
    deny "git-guard: '$why' changes repo or remote state. Gobind's rule: read-only git only (status, log, diff, show, blame). Ask him to run it, or ask him for /gobind:git-allow <branch> if he wants you to own a branch."
  else
    deny "git-guard: '$why' is blocked on '$BRANCH' even with the grant for '$GRANT'. main/master are never touched by an agent; only the granted feature branch is."
  fi
}

# config_writes <word>...
#   Decide whether "git config <words>" would change configuration.
#   Returns 0 (true) for a write and 1 (false) for a read.
#
#   Words are read left to right:
#     --get, --get-all, --get-regexp, --get-urlmatch, --get-color,
#     --get-colorbool, --list, -l                      -> read, stop
#     --unset, --unset-all, --add, --replace-all, --edit, -e,
#     --rename-section, --remove-section                -> write, stop
#     -f/--file, --blob, --default, --type, --comment, --value
#                                                       -> skip it and its value
#     any other option (--global, --show-origin, ...)   -> skip
#     anything else                                     -> a positional word
#   Then the positional words decide:
#     first is get or list                  -> read  (git 2.46+ syntax)
#     first is set, unset, edit, rename-section or remove-section
#                                           -> write (git 2.46+ syntax)
#     two or more, as in "user.name Alice"  -> write
#     zero or one, as in "user.name"        -> read
config_writes() {
  local -a pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|--list|-l) return 1;;
      --unset|--unset-all|--add|--replace-all|--edit|-e|--rename-section|--remove-section) return 0;;
      # Skip the option, then its value if there is one. A plain `shift 2`
      # would do nothing when the value is missing and loop forever.
      -f|--file|--blob|--default|--type|--comment|--value) shift; [ $# -gt 0 ] && shift;;
      -*) shift;;
      *) pos+=("$1"); shift;;
    esac
  done
  case "${pos[0]:-}" in
    get|list) return 1;;
    set|unset|edit|rename-section|remove-section) return 0;;
  esac
  [ "${#pos[@]}" -ge 2 ]
}

# Check each simple command separately. "npm test && git commit" is thus
# judged by its "git commit" part.
#
# The input comes from process substitution, < <(...), rather than a pipe.
# With a pipe, the while loop would run in a subshell, and the `exit` inside
# deny would only leave that subshell instead of ending the hook with the
# decision.
while IFS= read -r seg; do
  # Normalise the piece, as described in the header:
  #   tr -d          remove all double and single quotes
  #   1st sed rule   strip leading whitespace
  #   2nd sed rule   strip any run of wrappers, shell keywords and VAR=value
  #                  assignments in front of the real command
  #   3rd sed rule   turn /any/path/git or /any/path/gh into plain git or gh
  seg="$(printf '%s' "$seg" | tr -d "\"'" | sed -E 's/^[[:space:]]+//; s/^((sudo|env|command|exec|eval|nohup|time|if|then|else|elif|do|while|until|!|\{)[[:space:]]+|(bash|sh|zsh)[[:space:]]+-c[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s#^[^[:space:]]*/(git|gh)([[:space:]]|$)#\1\2#')"
  case "$seg" in
    git\ *|git)
      # Load the piece's words into $1, $2, ... and drop "git" itself.
      # $seg is unquoted on purpose so the shell splits it into words;
      # globbing is off (set -f above), so * stays a literal character.
      # tokens after 'git', skipping global options like -C <dir> or -c k=v
      set -- $seg; shift
      # Skip git's global options so $1 becomes the subcommand:
      #   -C <dir>, -c <k=v>, --git-dir <d>, --work-tree <d>   take a value
      #   any other -x or --long option                        stands alone
      # For options with a value, shift the option first and then the value
      # only if one exists. A plain `shift 2` does nothing when the value is
      # missing ("git -C" at the end of a command), which used to make this
      # loop spin until the hook timed out.
      while [ $# -gt 0 ]; do
        case "$1" in -C|-c|--git-dir|--work-tree) shift; [ $# -gt 0 ] && shift;; --*|-*) shift;; *) break;; esac
      done
      # $sub is the subcommand, such as commit. $rest is its arguments,
      # joined with spaces.
      sub="${1:-}"; shift || true; rest="$*"
      # "git" alone, or only options: nothing to judge.
      [ -z "$sub" ] && continue

      # ---- rule 1: read-only subcommands ----------------------------------
      if printf '%s' "$sub" | grep -Eq "$READ_ONLY"; then
        # a few read-only subcommands have mutating flags
        case "$sub" in
          # Listing remotes is fine; changing them is not.
          remote) printf '%s' "$rest" | grep -Eq '^(add|remove|rm|rename|set-url|prune)' && deny_git "git remote $rest";;
          # Reads such as "git config user.name" pass; writes are denied.
          # $rest is unquoted so each word becomes its own argument.
          config) config_writes $rest && deny_git "git config $rest";;
          # Listing worktrees is fine; creating or changing them is not.
          worktree) printf '%s' "$rest" | grep -Eq '^(add|remove|prune|move|lock|unlock)' && deny_git "git worktree $rest";;
          # Showing the reflog is fine; expiring or deleting entries is not.
          reflog) printf '%s' "$rest" | grep -Eq '^(expire|delete)' && deny_git "git reflog $rest";;
        esac
        # Read-only and not a mutating form: go to the next piece.
        continue
      fi

      # ---- rule 2: subcommands whose meaning depends on their arguments ----
      case "$sub" in
        branch)
          # Delete (-d/-D/--delete), move (-m/-M/--move), copy (-c/-C/--copy),
          # upstream changes, or editing the description: denied.
          printf '%s' "$rest" | grep -Eq -- '(^|[[:space:]])(-[dDmMcC]|--delete|--move|--copy|--set-upstream-to|-u|--unset-upstream|--edit-description)([[:space:]]|$)' && deny_git "git branch $rest"
          # Outside list mode, any word that is not an option names a branch
          # to create: "git branch new", "git branch new start-point",
          # "git branch -v new". List mode is on when one of these flags is
          # present: --list/-l, -a/--all, -r/--remotes, --contains,
          # --no-contains, --merged, --no-merged, --points-at, --show-current.
          # (git refuses a branch name after -a or -r, so those are safe.)
          # [^-[:space:]] means: the word starts with neither "-" nor a space.
          # 'git branch <name>' creates a branch
          if ! printf '%s' "$rest" | grep -Eq -- '(^|[[:space:]])(--list|-l|-a|--all|-r|--remotes|--contains|--no-contains|--merged|--no-merged|--points-at|--show-current)([[:space:]=]|$)'; then
            printf '%s' "$rest" | grep -Eq '(^|[[:space:]])[^-[:space:]]' && deny_git "git branch $rest"
          fi
          # Anything else, such as bare "git branch" or "--list feat*", lists.
          continue;;
        # stash list / stash show read; push, pop, drop, apply, clear write.
        stash) printf '%s' "$rest" | grep -Eq '^(list|show)' && continue; deny_git "git stash $rest";;
        # Bare "git tag" or a list form reads; anything else creates or deletes.
        tag) [ -z "$rest" ] && continue; printf '%s' "$rest" | grep -Eq '^(-l|--list|-n)' && continue; deny_git "git tag $rest";;
        # fetch changes remote-tracking refs but not branches or the working
        # tree. It is allowed only with a grant.
        fetch) [ -z "$GRANT" ] && deny_git "git fetch"; continue;;
      esac

      # ---- rule 3: everything else is a mutation ---------------------------
      # everything else mutates: commit push pull merge rebase reset checkout switch restore
      # clean cherry-pick revert am apply rm mv init add notes submodule filter-branch gc prune
      if [ -n "$GRANT" ]; then
        # 3a. Currently ON a protected branch: block commands that would write
        #     to it. is_main_branch also covers trunk and production.
        # grant present: block anything aimed at main/master, and anything while ON main
        is_main_branch "$BRANCH" && case "$sub" in commit|push|merge|rebase|reset|am|apply|revert|cherry-pick|add|rm|mv|restore) deny_git "git $sub (on $BRANCH)";; esac
        # 3b. Arguments name main or master as a whole word; "/" and ":" also
        #     count as boundaries, as in origin/main or HEAD:main. Block
        #     commands that could move that branch or switch onto it.
        printf '%s' "$rest" | grep -Eq '(^|[[:space:]:/])(main|master)([[:space:]]|$)' && case "$sub" in push|merge|rebase|reset|checkout|switch) deny_git "git $sub $rest";; esac
        # 3c. Dangerous push flags: force, force-with-lease, mirror, all
        #     branches, or deleting a remote branch.
        case "$sub" in push) printf '%s' "$rest" | grep -Eq -- '(--force|-f\b|--force-with-lease|--mirror|--all|--delete|-d\b)' && deny_git "git push $rest";; esac
        # 3d. A grant for one specific branch. When the current branch is
        #     known and differs, block history-writing commands. checkout and
        #     switch stay allowed so the agent can move to the granted branch.
        if [ "$GRANT" != "*" ] && [ -n "$BRANCH" ] && [ "$BRANCH" != "$GRANT" ]; then
          case "$sub" in commit|push|merge|rebase|reset|revert|cherry-pick|am|apply) deny_git "git $sub on '$BRANCH' (grant is for '$GRANT')";; esac
        fi
        # Passed every check that applies with a grant: allowed.
        continue
      fi
      # No grant: every mutation is denied.
      deny_git "git $sub $rest"
      ;;
    # ---- rule 4: GitHub CLI -------------------------------------------------
    gh\ *)
      # Only write actions on pr / release / issue / repo are checked. Reads
      # such as "gh pr view" or "gh issue list" pass. The action must be the
      # third word, followed by a space or the end of the piece.
      printf '%s' "$seg" | grep -Eq '^gh[[:space:]]+(pr|release|issue|repo)[[:space:]]+(create|merge|close|delete|edit|reopen|comment|review|ready)([[:space:]]|$)' && {
        # Without a grant, every such write is denied.
        [ -z "$GRANT" ] && deny_git "$seg"
        # With a grant, merging and deleting remain the user's call. Only
        # the action word is checked, so a title containing "merge" is fine.
        printf '%s' "$seg" | grep -Eq '^gh[[:space:]]+(pr|release|issue|repo)[[:space:]]+(merge|delete)([[:space:]]|$)' && deny_git "$seg"
      }
      ;;
  esac
done < <(segments "$CMD")
# No piece was denied.
allow
