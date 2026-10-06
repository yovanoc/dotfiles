#!/usr/bin/env bash
# Summarize direct Pi tool calls only; nested calls inside codemode are uncounted.
set -o pipefail

usage() {
  cat <<'EOF'
Usage: pi-session-audit.sh [--since ISO_TIMESTAMP] [--sessions-dir DIR] [--json]

Summarize metadata from Pi session JSONL files (never prompts or tool arguments).
--since accepts an ISO timestamp with an offset; naive timestamps are local time.
The default window is the last 48 hours.
EOF
}

error() {
  printf 'pi-session-audit.sh: %s\n' "$1" >&2
  exit 2
}

since=
sessions_dir="$HOME/.pi/agent/sessions"
json_output=false
while (($#)); do
  case "$1" in
    --since)
      (($# >= 2)) || error 'missing value for --since'
      since=$2
      shift 2
      ;;
    --since=*) since=${1#*=}; shift ;;
    --sessions-dir)
      (($# >= 2)) || error 'missing value for --sessions-dir'
      sessions_dir=$2
      shift 2
      ;;
    --sessions-dir=*) sessions_dir=${1#*=}; shift ;;
    --json) json_output=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) error "unknown argument: $1" ;;
  esac
done

if [[ $sessions_dir == '~' ]]; then
  sessions_dir=$HOME
elif [[ $sessions_dir == '~/'* ]]; then
  sessions_dir="$HOME/${sessions_dir#~/}"
fi

if ! JQ=$(command -v jq); then
  error 'jq is required; install it with `brew install jq` (or your system package manager)'
fi
if [[ ! -d $sessions_dir ]]; then
  error 'sessions directory does not exist or is not a directory'
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
filter="$script_dir/pi-session-audit.jq"

parse_local_time() {
  local value=$1 wall seconds fraction
  [[ $value =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt\ ]([0-9]{2}:[0-9]{2}:[0-9]{2})(\.([0-9]+))?$ ]] || return 1
  wall="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}"
  fraction=${BASH_REMATCH[4]:-}
  if seconds=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$wall" '+%s' 2>/dev/null); then
    :
  elif seconds=$(date -d "$wall" '+%s' 2>/dev/null); then
    :
  else
    return 1
  fi
  if [[ -n $fraction ]]; then
    "$JQ" -nr --arg seconds "$seconds" --arg fraction "$fraction" \
      '($seconds | tonumber) + ("0." + $fraction | tonumber)'
  else
    printf '%s\n' "$seconds"
  fi
}

if [[ -n $since ]]; then
  if [[ $since =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt\ ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$ ]]; then
    cutoff=$(parse_local_time "$since") || error 'invalid --since timestamp; expected ISO format'
  else
    cutoff=$("$JQ" -nr --arg mode time --arg time "$since" --arg path '' \
      --argjson cutoff 0 --arg window_start_local '' -f "$filter") || error 'invalid --since timestamp; expected ISO format'
    [[ -n $cutoff && $cutoff != null ]] || error 'invalid --since timestamp; expected ISO format'
  fi
else
  now=$(date +%s) || error 'could not read current time'
  cutoff=$((now - 172800))
fi
[[ $cutoff =~ ^-?[0-9]+([.][0-9]+)?$ ]] || error 'could not parse --since timestamp'

window_start_local=$("$JQ" -nr --argjson cutoff "$cutoff" '
  ($cutoff | localtime) as $local
  | ($cutoff - ($local | mktime)) as $west
  | ($west | abs | floor) as $offset
  | ($local | strftime("%Y-%m-%dT%H:%M:%S")) as $date
  | ($offset / 3600 | floor) as $hours
  | ($offset % 3600 / 60 | floor) as $minutes
  | ($date + (if $west > 0 then "-" else "+" end)
     + (if $hours < 10 then "0" else "" end) + ($hours | tostring)
     + ":" + (if $minutes < 10 then "0" else "" end) + ($minutes | tostring))
') || error 'could not format local cutoff'

report=$(
  {
    while IFS= read -r -d '' path; do
      if summary=$("$JQ" -Rn --arg mode scan --arg time '' --arg path "$path" --argjson cutoff "$cutoff" \
        --arg window_start_local "$window_start_local" -f "$filter" < "$path" 2>/dev/null); then
        printf '%s\n' "$summary"
      else
        printf '%s\n' '{"_unreadable":true}'
      fi
    done < <(find "$sessions_dir" -type f -name '*.jsonl' -print0)
  } | "$JQ" -s --arg mode aggregate --arg time '' --arg path '' --argjson cutoff "$cutoff" \
      --arg window_start_local "$window_start_local" -f "$filter"
)
status=$?
((status == 0)) || exit "$status"

if [[ $json_output == true ]]; then
  printf '%s\n' "$report" | "$JQ" -S .
else
  printf '%s\n' "$report" | "$JQ" -r '
    def counts: if length == 0 then "none" else (to_entries | sort_by(.key) | map("\(.key)=\(.value)") | join(", ")) end;
    . as $r
    | "Window start (local): \($r.window_start_local)",
      "Main sessions: \($r.main_sessions.older_with_activity // 0) older, \($r.main_sessions.created_within_window // 0) created in window",
      "Forks: \($r.fork_sessions.older_with_activity // 0) older, \($r.fork_sessions.created_within_window // 0) created in window",
      "Workers identified by session_info: \($r.workers.sessions) (\($r.workers.types | counts))",
      "Bash timeouts: workers calls=\($r.bash_timeouts.workers.calls), set=\($r.bash_timeouts.workers.timeout_argument_present), >3600s=\($r.bash_timeouts.workers.timeout_over_3600s); nonworker/coordinators calls=\($r.bash_timeouts.nonworker_coordinators.calls), set=\($r.bash_timeouts.nonworker_coordinators.timeout_argument_present), >3600s=\($r.bash_timeouts.nonworker_coordinators.timeout_over_3600s)",
      "Bash timeout values: workers \($r.bash_timeouts.workers.by_value | counts); nonworker/coordinators \($r.bash_timeouts.nonworker_coordinators.by_value | counts)",
      "Agent dispatches: \($r.agent_dispatches.total); max_turns \($r.agent_dispatches.max_turns | counts); model \($r.agent_dispatches.model | counts); thinking \($r.agent_dispatches.thinking | counts); background \($r.agent_dispatches.background | counts); resume \($r.agent_dispatches.resume | counts)",
      "Unique terminal notification statuses: \($r.terminal_notification_statuses_unique | counts)",
      "get_subagent_result: \($r.get_subagent_result.attempts) attempts, \($r.get_subagent_result.misses) misses (\($r.get_subagent_result.unique_missed_targets) unique targets, \($r.get_subagent_result.duplicate_misses) duplicate misses)",
      "Observed worker-span overlap proxy: \($r.workers.max_concurrency_observed_span_upper_bound)",
      "Scanned \($r.scan.files) files; malformed lines \($r.scan.malformed_lines); unreadable files \($r.scan.unreadable_files)",
      "Limitations: \($r.limitations[0])",
      "              \($r.limitations[1])"
  '
fi
