#!/usr/bin/env bash
# =============================================================================
# server-guard.sh - PreToolUse(Bash) hook: never kill or duplicate the dev server
# =============================================================================
#
# PreToolUse(Bash): Gobind usually has his own dev server running. Never kill it; reuse it.
#
# WHY
#   Agents often "get a clean start" by killing every node process or
#   whatever holds port 3000. That takes down the user's running dev server,
#   and can take down editors or this Claude Code session too. Starting a
#   second server on a busy port fails or silently picks another port.
#
# WHAT IS DENIED, CHECKED FOR EACH SIMPLE COMMAND
#   1. Blanket kills by process name: pkill or killall of node, next,
#      next-server, vite, pnpm, npm, bun, deno, python/python3, uvicorn or
#      gunicorn. Also `fuser -k`, which kills whatever owns a port or file.
#   2. `kill <pid>` when that PID is listening on a TCP port.
#   3. Starting a dev server (npm/pnpm/yarn/bun dev|start|serve|preview, next,
#      vite, nuxt, astro, ...) on a port that something already listens on.
#
# HOW PORTS ARE DISCOVERED
#   `ss -ltnpH` lists listening TCP sockets with their owning processes.
#     -l listening   -t TCP   -n numeric ports   -p show process   -H no header
#   Without root, ss only shows process info for the current user's
#   processes. When ss is missing or shows nothing, checks 2 and 3 find no
#   owner and allow the command.
#
# PORT GUESSING FOR CHECK 3
#   An explicit --port N, --port=N, -p N, -pN or PORT=N is used when present.
#   Otherwise vite and astro default to 5173, and everything else to 3000.
# =============================================================================

# Load shared helpers and read the hook JSON from stdin.
source "$(dirname "$0")/lib.sh"

# Only Bash commands are relevant.
[ "$TOOL_NAME" = "Bash" ] || allow
CMD="$(jget '.tool_input.command')"; [ -z "$CMD" ] && allow

# listeners
#   Every listening TCP socket, one per line, with process info. Column 4 is
#   the local address:port, and the last column holds users:(("name",pid=N,..)).
listeners() { ss -ltnpH 2>/dev/null; }

# port_owner <port>
#   Print the PID of the first process listening on <port>, or nothing.
#   awk keeps lines whose column 4 ends in ":<port>". The pattern is built
#   from p":<port>" followed by "$", which matches both 0.0.0.0:3000 and
#   [::]:3000. Then grep takes the first pid=N and cut keeps the number.
port_owner() { listeners | awk -v p=":$1" '$4 ~ p"$" {print $0}' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2; }

# pid_ports <pid>
#   Print the ports <pid> listens on, space-separated, or nothing.
#   \b stops pid=12 from also matching pid=123. sed removes everything up to
#   the last ":" to leave only the port. sort -u removes the IPv4/IPv6
#   duplicates.
pid_ports()  { listeners | grep -E "pid=$1\b" | awk '{print $4}' | sed -E 's/.*://' | sort -u | tr '\n' ' '; }

# pid_cmd <pid>
#   The process's command line, cut to 80 characters, used in denial messages.
pid_cmd()    { ps -o args= -p "$1" 2>/dev/null | cut -c1-80; }

# Check each simple command of the command line. Process substitution rather
# than a pipe keeps the loop in this shell, so `exit` inside deny ends the hook.
while IFS= read -r seg; do
  # Strip leading whitespace left by segments().
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//')"

  # ---- 1. blanket kills ------------------------------------------------------
  # Optional sudo, then pkill or killall, any number of option words, then one
  # of the dev-runtime names as a whole word.
  # 1. blanket process kills that take Claude Code, VS Code and his server down together
  if printf '%s' "$seg" | grep -Eq '^(sudo[[:space:]]+)?(pkill|killall)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(node|next|next-server|vite|pnpm|npm|bun|deno|python3?|uvicorn|gunicorn)([[:space:]]|$)'; then
    deny "server-guard: '$seg' kills every matching process, including Gobind's own dev server and possibly this session. Find the one PID with 'ss -ltnp' or 'lsof -i :PORT' and ask him before killing anything that serves a port."
  fi
  # fuser with -k among its options kills every process using the target.
  printf '%s' "$seg" | grep -Eq '^(sudo[[:space:]]+)?fuser[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-k' && deny "server-guard: fuser -k kills whatever owns that port. That is probably Gobind's dev server. Reuse it, or ask him."

  # ---- 2. kill <pid> of a listening process ---------------------------------
  # Optional sudo, kill, optional option words, then at least one number.
  # 2. kill <pid> where pid owns a listening port
  if printf '%s' "$seg" | grep -Eq '^(sudo[[:space:]]+)?kill([[:space:]]+-[^[:space:]]+)*[[:space:]]+[0-9]+'; then
    # Take every number that follows a space or starts the segment. A signal
    # such as -9 is skipped, because its digits follow "-".
    for pid in $(printf '%s' "$seg" | grep -oE '(^|[[:space:]])[0-9]+' | tr -d ' '); do
      ports="$(pid_ports "$pid")"
      [ -n "$ports" ] && deny "server-guard: PID $pid serves port(s) $ports ($(pid_cmd "$pid")). Gobind's rule: never kill or restart a running server to get a clean start. Reuse it; ask him if it truly must go."
    done
  fi

  # ---- 3. a second dev server on a busy port --------------------------------
  # Either a package-manager script (dev, start, serve, preview), or a known
  # dev-server binary used as a whole word.
  # 3. starting a dev server on a port that is already served
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])(pnpm|npm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(dev|start|serve|preview)([[:space:]]|$)|(^|[[:space:]])(next|vite|nuxt|astro|remix|nodemon|ts-node-dev|tsx watch|vercel dev|wrangler dev|http-server|serve|live-server)([[:space:]]|$)'; then
    # Explicit port, if any: the first --port N, --port=N, -p N, -pN or PORT=N.
    port="$(printf '%s' "$seg" | grep -oE -- '(--port[= ]|-p[= ]?|PORT=)[0-9]+' | grep -oE '[0-9]+$' | head -1)"
    # No explicit port: assume the framework default. The nuxt branch equals
    # the fallback and is listed only for clarity.
    if [ -z "$port" ]; then
      case "$seg" in *vite*|*astro*) port=5173;; *nuxt*) port=3000;; *) port=3000;; esac
    fi
    # Deny when something is already listening there and point to reusing it.
    owner="$(port_owner "$port")"
    [ -n "$owner" ] && deny "server-guard: port $port is already served by PID $owner ($(pid_cmd "$owner")). That is most likely Gobind's own dev server. Reuse it (curl http://localhost:$port) instead of starting another; ask him if you think it must be restarted."
  fi
done < <(segments "$CMD")
# No segment was denied.
allow
