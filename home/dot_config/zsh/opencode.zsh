# One shared OpenCode backend on 4097; clients attach from their current directory.
unalias oc oc-server oc-stop oc-restart oc-update 2>/dev/null

typeset -g _OC_SERVER_HOST="127.0.0.1"
typeset -g _OC_SERVER_BIND="0.0.0.0"
typeset -g _OC_SERVER_PORT="4097"
typeset -g _OC_SERVER_PASSWORD_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/opencode/server-password"
typeset -g _OC_SERVER_URL="http://${_OC_SERVER_HOST}:${_OC_SERVER_PORT}"

# The password lives outside this repo, so this file is safe to commit publicly.
# Generated once per machine on first use; nothing to copy between machines.
function _oc_server_password() {
  [[ -s "$_OC_SERVER_PASSWORD_FILE" ]] || {
    mkdir -p "${_OC_SERVER_PASSWORD_FILE:h}" || return 1
    ( umask 077; { openssl rand -base64 24 2>/dev/null || head -c 24 /dev/urandom | base64; } | tr -d '\n' > "$_OC_SERVER_PASSWORD_FILE" ) || return 1
    print -u2 "generated a new opencode server password at ${_OC_SERVER_PASSWORD_FILE}"
  }
  cat "$_OC_SERVER_PASSWORD_FILE"
}

function _oc_backend_pid() {
  /usr/sbin/lsof -tiTCP:"$_OC_SERVER_PORT" -sTCP:LISTEN 2>/dev/null
}

function _oc_backend_ready() {
  local pid=$(_oc_backend_pid)
  [[ -n "$pid" && "$pid" != *$'\n'* && "$(ps -o command= -p "$pid")" == *"opencode serve"*"--port ${_OC_SERVER_PORT}"* ]]
}

function _oc_backend_start() {
  _oc_backend_ready && return
  [[ -n "$(_oc_backend_pid)" ]] && { print -u2 "refusing to start: unexpected or multiple listeners on port ${_OC_SERVER_PORT}"; return 1; }
  (
    local lock="${TMPDIR:-/tmp}/opencode-${_OC_SERVER_PORT}.lock"
    if ! mkdir "$lock" 2>/dev/null; then
      local i
      for i in {1..40}; do _oc_backend_ready && return; sleep 0.25; done
      print -u2 "timed out waiting for the opencode backend startup lock"
      return 1
    fi
    trap 'rmdir "$lock" 2>/dev/null' EXIT
    _oc_backend_ready && return
    [[ -n "$(_oc_backend_pid)" ]] && { print -u2 "refusing to start: port ${_OC_SERVER_PORT} became occupied"; return 1; }
    print "opencode backend not up — starting on ${_OC_SERVER_BIND}:${_OC_SERVER_PORT}…"
    (OPENCODE_SERVER_PASSWORD="$(_oc_server_password)" opencode serve --hostname "$_OC_SERVER_BIND" --port "$_OC_SERVER_PORT" >/dev/null 2>&1 &)
    local i
    for i in {1..40}; do _oc_backend_ready && return; sleep 0.25; done
    print -u2 "opencode backend failed to start"
    return 1
  )
}

function oc() {
  emulate -L zsh
  _oc_backend_start || return
  OPENCODE_SERVER_PASSWORD="$(_oc_server_password)" opencode attach "$_OC_SERVER_URL" --dir "$PWD" "$@"
}

function oc-stop() {
  emulate -L zsh
  local pid=$(_oc_backend_pid)
  if [[ -n "$pid" ]]; then
    [[ "$(ps -o command= -p "$pid")" == *"opencode serve"*"--port ${_OC_SERVER_PORT}"* ]] || {
      print -u2 "refusing to kill unexpected process $pid on port ${_OC_SERVER_PORT}"
      return 1
    }
    kill "$pid" || return
    local i
    for i in {1..40}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$pid" 2>/dev/null && { print -u2 "backend $pid did not stop"; return 1; }
  fi
}

function oc-restart() {
  emulate -L zsh
  oc-stop || return
  _oc_backend_start
}

function oc-update() {
  emulate -L zsh
  oc-stop || return
  opencode upgrade "$@" || { _oc_backend_start; return 1; }
  _oc_backend_start || return
  print "updated backend; reopen attached oc clients to use the new TUI binary"
}

# Delete sessions untouched for more than N days, then reclaim database space.
function ocprune() {
  emulate -L zsh
  local days=${1:?usage: ocprune <days>}
  local db=~/.local/share/opencode/opencode.db
  pgrep -x opencode >/dev/null && { print -u2 "opencode still running — close all oc clients, then run oc-stop"; return 1; }
  local cutoff=$(( ($(date +%s) - days * 86400) * 1000 ))
  local n=$(sqlite3 "$db" "SELECT count(*) FROM session WHERE time_updated < $cutoff;")
  (( n > 0 )) || { print "nothing older than ${days}d"; return 0; }
  print -n "delete $n sessions older than ${days}d? [y/N] "
  read -q || { print; return 1; }
  print
  sqlite3 "$db" "PRAGMA foreign_keys=ON; DELETE FROM session WHERE time_updated < $cutoff;" || { print -u2 "delete failed"; return 1; }
  print "vacuuming (can take minutes on a big db)…"
  sqlite3 "$db" "VACUUM;"
  print "done → $(du -sh ~/.local/share/opencode | cut -f1) total"
}
